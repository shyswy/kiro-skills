---
name: kotlin-spring
description: |
  Kotlin + Spring Boot 개발 패턴 가이드. Spring Boot 3.x, WebFlux, Coroutines, JPA,
  Gradle Kotlin DSL, 테스트, 에러 핸들링, 프로젝트 구조를 다룬다.
  Kotlin으로 Spring 애플리케이션을 작성하거나, 코루틴 기반 비동기 처리, Spring Data,
  보안, 배치 등을 구현할 때 사용한다.
  트리거: Kotlin, Spring Boot, Spring, WebFlux, 코루틴, coroutine, Gradle, Spring Data,
  JPA, R2DBC, Spring Security, 코틀린, 스프링, 스프링부트, 그래들,
  백엔드, 서버, DI, 의존성 주입, 코틀린 스프링, Kotlin Spring,
  suspend, Flow, Ktor, kotlinx, serialization
license: MIT
---

# Kotlin + Spring Boot Patterns

## 버전 기준
- Kotlin: 1.9+ (K2 컴파일러 옵션)
- Spring Boot: 3.2+ (Java 17 필수, 21 권장)
- Gradle: 8.x + Kotlin DSL (build.gradle.kts)
- JDK: 17 (LTS) 또는 21 (LTS, Virtual Threads)

---

## 프로젝트 구조

### Layered Architecture (기본)
```
src/main/kotlin/com/example/app/
├── config/              # @Configuration, SecurityConfig, WebConfig
├── controller/          # @RestController, Request/Response DTO
├── service/             # @Service, 비즈니스 로직
├── repository/          # @Repository, Spring Data 인터페이스
├── domain/              # Entity, Value Object, Enum
├── dto/                 # Request/Response DTO (data class)
├── exception/           # 커스텀 예외, GlobalExceptionHandler
├── util/                # Extension functions, 유틸
└── Application.kt
```

### Hexagonal / Clean Architecture (대규모)
```
src/main/kotlin/com/example/app/
├── adapter/
│   ├── in/web/          # Controller (Driving adapter)
│   ├── in/event/        # Event consumer
│   └── out/persistence/ # JPA/R2DBC 구현체 (Driven adapter)
├── application/
│   ├── port/in/         # Use case 인터페이스
│   ├── port/out/        # Repository 인터페이스
│   └── service/         # Use case 구현
├── domain/
│   ├── model/           # Entity, Value Object
│   └── event/           # Domain event
└── infrastructure/
    └── config/          # Spring config, Bean 등록
```

---

## Kotlin 핵심 패턴 (Spring 맥락)

### Data Class & DTO
```kotlin
// Request DTO — validation 포함
data class CreateUserRequest(
    @field:NotBlank val name: String,
    @field:Email val email: String,
    @field:Size(min = 8) val password: String
)

// Response DTO — 팩토리 메서드로 변환
data class UserResponse(
    val id: Long,
    val name: String,
    val email: String
) {
    companion object {
        fun from(user: User) = UserResponse(
            id = user.id!!,
            name = user.name,
            email = user.email
        )
    }
}
```

### Sealed Class 에러 모델링
```kotlin
sealed class DomainException(
    val errorCode: String,
    override val message: String
) : RuntimeException(message) {

    class NotFound(resource: String, id: Any) :
        DomainException("NOT_FOUND", "$resource not found: $id")

    class AlreadyExists(resource: String, key: Any) :
        DomainException("ALREADY_EXISTS", "$resource already exists: $key")

    class ValidationFailed(reason: String) :
        DomainException("VALIDATION_FAILED", reason)

    class Unauthorized(reason: String = "인증이 필요합니다") :
        DomainException("UNAUTHORIZED", reason)
}
```

### Extension Function 활용
```kotlin
// Entity → Response 변환
fun User.toResponse() = UserResponse(id = id!!, name = name, email = email)

// Nullable 안전 처리
fun <T> T?.orThrow(message: String): T =
    this ?: throw DomainException.NotFound("Resource", message)
```

### Value Class (타입 안전 래퍼)
```kotlin
@JvmInline
value class UserId(val value: Long)

@JvmInline
value class Email(val value: String) {
    init { require(value.contains("@")) { "Invalid email: $value" } }
}
```

---

## Spring Boot 설정

### build.gradle.kts 기본
```kotlin
plugins {
    kotlin("jvm") version "1.9.25"
    kotlin("plugin.spring") version "1.9.25"
    kotlin("plugin.jpa") version "1.9.25"  // no-arg for JPA
    id("org.springframework.boot") version "3.3.0"
    id("io.spring.dependency-management") version "1.1.6"
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin")
    implementation("org.jetbrains.kotlin:kotlin-reflect")

    runtimeOnly("com.h2database:h2")
    runtimeOnly("org.postgresql:postgresql")

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("io.mockk:mockk:1.13.12")
}

kotlin {
    compilerOptions {
        freeCompilerArgs.addAll("-Xjsr305=strict")  // null-safety for Spring
    }
}
```

### application.yml 패턴
```yaml
spring:
  profiles:
    active: local
  datasource:
    url: jdbc:postgresql://localhost:5432/mydb
    username: ${DB_USERNAME:postgres}
    password: ${DB_PASSWORD:postgres}
  jpa:
    hibernate:
      ddl-auto: validate
    open-in-view: false  # 항상 false 권장
    properties:
      hibernate:
        default_batch_fetch_size: 100

---
spring:
  config:
    activate:
      on-profile: local
  jpa:
    hibernate:
      ddl-auto: create-drop
    show-sql: true
```

---

## Controller 패턴

```kotlin
@RestController
@RequestMapping("/api/v1/users")
class UserController(
    private val userService: UserService
) {
    @PostMapping
    fun create(@Valid @RequestBody request: CreateUserRequest): ResponseEntity<UserResponse> {
        val user = userService.create(request)
        return ResponseEntity.status(HttpStatus.CREATED).body(user.toResponse())
    }

    @GetMapping("/{id}")
    fun getById(@PathVariable id: Long): ResponseEntity<UserResponse> {
        val user = userService.getById(id)
        return ResponseEntity.ok(user.toResponse())
    }

    @GetMapping
    fun search(
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int
    ): ResponseEntity<Page<UserResponse>> {
        val users = userService.search(PageRequest.of(page, size))
        return ResponseEntity.ok(users.map { it.toResponse() })
    }
}
```

---

## Service 패턴

```kotlin
@Service
@Transactional(readOnly = true)
class UserService(
    private val userRepository: UserRepository
) {
    fun getById(id: Long): User =
        userRepository.findByIdOrNull(id)
            ?: throw DomainException.NotFound("User", id)

    @Transactional
    fun create(request: CreateUserRequest): User {
        if (userRepository.existsByEmail(request.email)) {
            throw DomainException.AlreadyExists("User", request.email)
        }
        return userRepository.save(
            User(name = request.name, email = request.email, password = request.password)
        )
    }
}
```

---

## Repository 패턴 (Spring Data JPA)

```kotlin
interface UserRepository : JpaRepository<User, Long> {
    fun existsByEmail(email: String): Boolean
    fun findByEmail(email: String): User?

    @Query("SELECT u FROM User u WHERE u.name LIKE %:keyword%")
    fun searchByName(@Param("keyword") keyword: String, pageable: Pageable): Page<User>
}
```

### Entity 설계
```kotlin
@Entity
@Table(name = "users")
class User(
    @Column(nullable = false)
    var name: String,

    @Column(nullable = false, unique = true)
    var email: String,

    @Column(nullable = false)
    var password: String,

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    val id: Long? = null
) {
    // equals/hashCode는 id 기반 (JPA 프록시 호환)
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is User) return false
        return id != null && id == other.id
    }
    override fun hashCode(): Int = javaClass.hashCode()
}
```

---

## 에러 핸들링 (글로벌)

```kotlin
@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(DomainException.NotFound::class)
    fun handleNotFound(e: DomainException.NotFound): ResponseEntity<ErrorResponse> =
        ResponseEntity.status(HttpStatus.NOT_FOUND)
            .body(ErrorResponse(e.errorCode, e.message))

    @ExceptionHandler(DomainException.AlreadyExists::class)
    fun handleConflict(e: DomainException.AlreadyExists): ResponseEntity<ErrorResponse> =
        ResponseEntity.status(HttpStatus.CONFLICT)
            .body(ErrorResponse(e.errorCode, e.message))

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(e: MethodArgumentNotValidException): ResponseEntity<ErrorResponse> {
        val errors = e.bindingResult.fieldErrors.associate { it.field to (it.defaultMessage ?: "") }
        return ResponseEntity.badRequest()
            .body(ErrorResponse("VALIDATION_FAILED", "입력값 검증 실패", errors))
    }

    @ExceptionHandler(Exception::class)
    fun handleUnexpected(e: Exception): ResponseEntity<ErrorResponse> {
        log.error(e) { "Unexpected error" }
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(ErrorResponse("INTERNAL_ERROR", "서버 내부 오류"))
    }

    companion object {
        private val log = KotlinLogging.logger {}
    }
}

data class ErrorResponse(
    val code: String,
    val message: String,
    val details: Map<String, String>? = null
)
```

---

## 비동기 / Coroutines (WebFlux)

### WebFlux + Coroutines 설정
```kotlin
// build.gradle.kts 추가
implementation("org.springframework.boot:spring-boot-starter-webflux")
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core")
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-reactor")
```

### Suspend Controller
```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(
    private val orderService: OrderService
) {
    @GetMapping("/{id}")
    suspend fun getById(@PathVariable id: Long): OrderResponse =
        orderService.getById(id).toResponse()

    @GetMapping
    fun getAll(): Flow<OrderResponse> =
        orderService.getAll().map { it.toResponse() }
}
```

### Coroutine Service 패턴
```kotlin
@Service
class OrderService(
    private val orderRepository: OrderRepository,
    private val paymentClient: PaymentClient,
    private val notificationClient: NotificationClient
) {
    // 동시 실행
    suspend fun getOrderWithDetails(orderId: Long): OrderDetail = coroutineScope {
        val order = async { orderRepository.findById(orderId) }
        val payment = async { paymentClient.getPayment(orderId) }
        OrderDetail(order.await(), payment.await())
    }

    // 순차 실행 (의존 관계)
    suspend fun processOrder(request: CreateOrderRequest): Order {
        val order = orderRepository.save(request.toEntity())
        val payment = paymentClient.charge(order.id!!, order.totalAmount)
        notificationClient.sendConfirmation(order, payment)
        return order
    }
}
```

---

## 테스트 (JUnit 5 기반)

### Unit Test (MockK)
```kotlin
@ExtendWith(MockKExtension::class)
class UserServiceTest {
    @MockK
    private lateinit var userRepository: UserRepository

    @InjectMockKs
    private lateinit var userService: UserService

    @Test
    fun `존재하지 않는 유저 조회 시 NotFound 예외`() {
        every { userRepository.findByIdOrNull(1L) } returns null

        assertThrows<DomainException.NotFound> {
            userService.getById(1L)
        }
    }

    @Test
    fun `유저 생성 성공`() {
        val request = CreateUserRequest("홍길동", "hong@example.com", "password123")
        every { userRepository.existsByEmail(any()) } returns false
        every { userRepository.save(any()) } returns User("홍길동", "hong@example.com", "pw", 1L)

        val result = userService.create(request)

        assertThat(result.name).isEqualTo("홍길동")
        verify(exactly = 1) { userRepository.save(any()) }
    }
}
```

### Integration Test
```kotlin
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
class UserControllerIntegrationTest(
    @Autowired val restTemplate: TestRestTemplate,
    @Autowired val userRepository: UserRepository
) {
    @BeforeEach
    fun setup() {
        userRepository.deleteAll()
    }

    @Test
    fun `유저 생성 API 정상 동작`() {
        val request = CreateUserRequest("테스트", "test@example.com", "password123")

        val response = restTemplate.postForEntity("/api/v1/users", request, UserResponse::class.java)

        assertThat(response.statusCode).isEqualTo(HttpStatus.CREATED)
        assertThat(response.body?.name).isEqualTo("테스트")
    }
}
```

### Slice Test
```kotlin
@WebMvcTest(UserController::class)
class UserControllerTest {
    @Autowired
    private lateinit var mockMvc: MockMvc

    @MockkBean
    private lateinit var userService: UserService

    @Test
    fun `GET users_id - 200 OK`() {
        every { userService.getById(1L) } returns User("홍길동", "hong@test.com", "pw", 1L)

        mockMvc.perform(get("/api/v1/users/1"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.name").value("홍길동"))
    }
}
```

---

## 성능 & 운영

- **N+1 문제**: `@EntityGraph`, `fetch join`, `default_batch_fetch_size`
- **커넥션 풀**: HikariCP (Spring Boot 기본), `maximumPoolSize` 적정 설정
- **캐시**: `@Cacheable` + Redis (spring-boot-starter-data-redis)
- **로깅**: kotlin-logging (SLF4J 래퍼), 구조화 로그 (JSON)
- **모니터링**: Micrometer + Prometheus + Actuator
- **GraalVM Native**: Spring Boot 3.x 네이티브 이미지 지원

---

## 주요 라이브러리 조합

| 용도 | 라이브러리 |
|------|-----------|
| JSON | Jackson + jackson-module-kotlin |
| Validation | spring-boot-starter-validation (Hibernate Validator) |
| 로깅 | kotlin-logging (io.github.oshai:kotlin-logging-jvm) |
| HTTP Client | WebClient (WebFlux) 또는 RestClient (Spring 6.1+) |
| 날짜/시간 | java.time (LocalDateTime, ZonedDateTime) |
| 테스트 Mock | MockK |
| 테스트 컨테이너 | Testcontainers |
| API 문서 | SpringDoc OpenAPI (Swagger UI) |
| 마이그레이션 | Flyway 또는 Liquibase |

---

## MCP 연동

이 스킬은 특정 MCP에 의존하지 않음. 코드 작성/리뷰/설계 가이드 목적.
- AWS Lambda 배포 시 → `aws-serverless-eda` 스킬 참조
- Docker 컨테이너화 시 → `docker-container` 스킬 참조
- CI/CD 파이프라인 시 → `gitops-cicd` 스킬 참조
- DB 설계/쿼리 최적화 시 → `rdb-optimization` 스킬 참조
