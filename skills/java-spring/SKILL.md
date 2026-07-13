---
name: java-spring
description: |
  Java + Spring Boot 개발 패턴 가이드. Spring Boot 3.x, Java 17/21, JPA, Security,
  Gradle/Maven 빌드, 테스트, 에러 핸들링, 프로젝트 구조를 다룬다.
  Java로 Spring 애플리케이션을 작성하거나, REST API, 배치, 메시징 등을 구현할 때 사용한다.
  트리거: Java, Spring Boot, Spring, Maven, Gradle, JPA, Hibernate, Spring Security,
  자바, 스프링, 스프링부트, 메이븐, 그래들, 백엔드, 서버, DI, 의존성 주입,
  Java Spring, Record, Virtual Threads, Spring Batch, Spring MVC
license: MIT
---

# Java + Spring Boot Patterns

## 버전 기준
- Java: 17 (LTS, 현재 한국 기업 표준) / 21 (LTS, Virtual Threads)
- Spring Boot: 3.2+ (Java 17 필수)
- Gradle: 8.x (Kotlin DSL 또는 Groovy DSL)
- Maven: 3.9+

---

## 프로젝트 구조

### Layered Architecture (기본)
```
src/main/java/com/example/app/
├── config/              # @Configuration, SecurityConfig, WebConfig
├── controller/          # @RestController, Request/Response DTO
├── service/             # @Service, 비즈니스 로직
├── repository/          # @Repository, Spring Data 인터페이스
├── domain/              # Entity, Value Object, Enum
├── dto/                 # Request/Response DTO (Record)
├── exception/           # 커스텀 예외, GlobalExceptionHandler
├── util/                # 유틸리티 클래스
└── Application.java
```

### Multi-Module (대규모)
```
project-root/
├── app-api/             # Web layer (Controller, DTO)
├── app-core/            # Business logic (Service, Domain)
├── app-infra/           # Infrastructure (JPA Entity, Repository Impl, Client)
├── app-common/          # 공유 유틸, 상수
└── build.gradle.kts     # Root build script
```

---

## Java 17+ 핵심 패턴

### Record (불변 DTO)
```java
// Request DTO
public record CreateUserRequest(
    @NotBlank String name,
    @Email String email,
    @Size(min = 8) String password
) {}

// Response DTO
public record UserResponse(Long id, String name, String email) {
    public static UserResponse from(User user) {
        return new UserResponse(user.getId(), user.getName(), user.getEmail());
    }
}

// Error Response
public record ErrorResponse(String code, String message, Map<String, String> details) {
    public ErrorResponse(String code, String message) {
        this(code, message, null);
    }
}
```

### Sealed Class (Java 17+)
```java
public sealed class DomainException extends RuntimeException
    permits DomainException.NotFound,
            DomainException.AlreadyExists,
            DomainException.ValidationFailed {

    private final String errorCode;

    protected DomainException(String errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    public String getErrorCode() { return errorCode; }

    public static final class NotFound extends DomainException {
        public NotFound(String resource, Object id) {
            super("NOT_FOUND", resource + " not found: " + id);
        }
    }

    public static final class AlreadyExists extends DomainException {
        public AlreadyExists(String resource, Object key) {
            super("ALREADY_EXISTS", resource + " already exists: " + key);
        }
    }

    public static final class ValidationFailed extends DomainException {
        public ValidationFailed(String reason) {
            super("VALIDATION_FAILED", reason);
        }
    }
}
```

### Pattern Matching (Java 21+)
```java
// instanceof 패턴
if (exception instanceof DomainException.NotFound e) {
    return ResponseEntity.status(404).body(new ErrorResponse(e.getErrorCode(), e.getMessage()));
}

// switch 패턴
return switch (exception) {
    case DomainException.NotFound e -> ResponseEntity.status(404).body(errorOf(e));
    case DomainException.AlreadyExists e -> ResponseEntity.status(409).body(errorOf(e));
    case DomainException.ValidationFailed e -> ResponseEntity.badRequest().body(errorOf(e));
};
```

### Virtual Threads (Java 21+)
```java
// application.yml
spring:
  threads:
    virtual:
      enabled: true  # Tomcat이 Virtual Threads 사용

// 수동 ExecutorService
@Bean
public ExecutorService virtualThreadExecutor() {
    return Executors.newVirtualThreadPerTaskExecutor();
}
```

---

## 빌드 설정

### build.gradle.kts (Gradle Kotlin DSL)
```kotlin
plugins {
    java
    id("org.springframework.boot") version "3.3.0"
    id("io.spring.dependency-management") version "1.1.6"
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    compileOnly("org.projectlombok:lombok")
    annotationProcessor("org.projectlombok:lombok")

    runtimeOnly("org.postgresql:postgresql")

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.withType<Test> {
    useJUnitPlatform()
}
```

### pom.xml (Maven)
```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.0</version>
</parent>

<properties>
    <java.version>21</java.version>
</properties>

<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-validation</artifactId>
    </dependency>
    <dependency>
        <groupId>org.projectlombok</groupId>
        <artifactId>lombok</artifactId>
        <optional>true</optional>
    </dependency>
</dependencies>
```

---

## Controller 패턴

```java
@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @PostMapping
    public ResponseEntity<UserResponse> create(@Valid @RequestBody CreateUserRequest request) {
        User user = userService.create(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(UserResponse.from(user));
    }

    @GetMapping("/{id}")
    public ResponseEntity<UserResponse> getById(@PathVariable Long id) {
        User user = userService.getById(id);
        return ResponseEntity.ok(UserResponse.from(user));
    }

    @GetMapping
    public ResponseEntity<Page<UserResponse>> search(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        Page<UserResponse> users = userService.search(PageRequest.of(page, size))
            .map(UserResponse::from);
        return ResponseEntity.ok(users);
    }
}
```

---

## Service 패턴

```java
@Service
@Transactional(readOnly = true)
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;

    public User getById(Long id) {
        return userRepository.findById(id)
            .orElseThrow(() -> new DomainException.NotFound("User", id));
    }

    @Transactional
    public User create(CreateUserRequest request) {
        if (userRepository.existsByEmail(request.email())) {
            throw new DomainException.AlreadyExists("User", request.email());
        }
        User user = User.builder()
            .name(request.name())
            .email(request.email())
            .password(request.password())
            .build();
        return userRepository.save(user);
    }
}
```

---

## Repository 패턴

```java
public interface UserRepository extends JpaRepository<User, Long> {
    boolean existsByEmail(String email);
    Optional<User> findByEmail(String email);

    @Query("SELECT u FROM User u WHERE u.name LIKE %:keyword%")
    Page<User> searchByName(@Param("keyword") String keyword, Pageable pageable);
}
```

### Entity 설계
```java
@Entity
@Table(name = "users")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name;

    @Column(nullable = false, unique = true)
    private String email;

    @Column(nullable = false)
    private String password;

    @Builder
    public User(String name, String email, String password) {
        this.name = name;
        this.email = email;
        this.password = password;
    }

    // 비즈니스 메서드
    public void updateName(String name) {
        this.name = name;
    }
}
```

---

## 에러 핸들링 (글로벌)

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(DomainException.NotFound.class)
    public ResponseEntity<ErrorResponse> handleNotFound(DomainException.NotFound e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
            .body(new ErrorResponse(e.getErrorCode(), e.getMessage()));
    }

    @ExceptionHandler(DomainException.AlreadyExists.class)
    public ResponseEntity<ErrorResponse> handleConflict(DomainException.AlreadyExists e) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
            .body(new ErrorResponse(e.getErrorCode(), e.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException e) {
        Map<String, String> errors = e.getBindingResult().getFieldErrors().stream()
            .collect(Collectors.toMap(
                FieldError::getField,
                fe -> fe.getDefaultMessage() != null ? fe.getDefaultMessage() : ""
            ));
        return ResponseEntity.badRequest()
            .body(new ErrorResponse("VALIDATION_FAILED", "입력값 검증 실패", errors));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleUnexpected(Exception e) {
        log.error("Unexpected error", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ErrorResponse("INTERNAL_ERROR", "서버 내부 오류"));
    }
}
```

---

## 테스트 (JUnit 5)

### Unit Test (Mockito)
```java
@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    @Mock
    private UserRepository userRepository;

    @InjectMocks
    private UserService userService;

    @Test
    @DisplayName("존재하지 않는 유저 조회 시 NotFound 예외")
    void getById_notFound() {
        given(userRepository.findById(1L)).willReturn(Optional.empty());

        assertThatThrownBy(() -> userService.getById(1L))
            .isInstanceOf(DomainException.NotFound.class)
            .hasMessageContaining("User not found: 1");
    }

    @Test
    @DisplayName("유저 생성 성공")
    void create_success() {
        var request = new CreateUserRequest("홍길동", "hong@example.com", "password123");
        given(userRepository.existsByEmail(any())).willReturn(false);
        given(userRepository.save(any())).willAnswer(inv -> inv.getArgument(0));

        User result = userService.create(request);

        assertThat(result.getName()).isEqualTo("홍길동");
        verify(userRepository, times(1)).save(any());
    }
}
```

### Integration Test
```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
class UserControllerIntegrationTest {

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private UserRepository userRepository;

    @BeforeEach
    void setup() {
        userRepository.deleteAll();
    }

    @Test
    @DisplayName("유저 생성 API 정상 동작")
    void createUser() {
        var request = new CreateUserRequest("테스트", "test@example.com", "password123");

        var response = restTemplate.postForEntity("/api/v1/users", request, UserResponse.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(response.getBody().name()).isEqualTo("테스트");
    }
}
```

### Slice Test (@WebMvcTest)
```java
@WebMvcTest(UserController.class)
class UserControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private UserService userService;

    @Test
    @DisplayName("GET /api/v1/users/{id} - 200 OK")
    void getById() throws Exception {
        User user = User.builder().name("홍길동").email("hong@test.com").password("pw").build();
        given(userService.getById(1L)).willReturn(user);

        mockMvc.perform(get("/api/v1/users/1"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.name").value("홍길동"));
    }
}
```

---

## 성능 & 운영

- **N+1 문제**: `@EntityGraph`, `JOIN FETCH`, `default_batch_fetch_size`
- **커넥션 풀**: HikariCP (`maximum-pool-size` 적정 설정, CPU cores * 2 + disk spindle)
- **캐시**: `@Cacheable` + Redis / Caffeine
- **로깅**: SLF4J + Logback, 구조화 로그 (JSON encoder)
- **모니터링**: Micrometer + Prometheus + Spring Actuator
- **API 문서**: SpringDoc OpenAPI (Swagger UI 자동 생성)
- **마이그레이션**: Flyway (버전 관리형 DDL)
- **Lombok**: `@Getter`, `@Builder`, `@RequiredArgsConstructor` (Entity에는 제한적 사용)

---

## 주요 라이브러리 조합

| 용도 | 라이브러리 |
|------|-----------|
| JSON | Jackson (Spring Boot 기본) |
| Validation | Hibernate Validator (spring-boot-starter-validation) |
| 로깅 | SLF4J + Logback |
| HTTP Client | RestClient (Spring 6.1+), WebClient, Feign |
| 날짜/시간 | java.time (LocalDateTime, ZonedDateTime) |
| 테스트 Mock | Mockito + BDDMockito |
| 테스트 컨테이너 | Testcontainers |
| API 문서 | SpringDoc OpenAPI 2.x |
| 마이그레이션 | Flyway |
| 코드 생성 | Lombok, MapStruct |
| Resilience | Resilience4j (CircuitBreaker, Retry, Bulkhead) |

---

## MCP 연동

이 스킬은 특정 MCP에 의존하지 않음. 코드 작성/리뷰/설계 가이드 목적.
- AWS Lambda 배포 시 → `aws-serverless-eda` 스킬 참조
- Docker 컨테이너화 시 → `docker-container` 스킬 참조
- CI/CD 파이프라인 시 → `gitops-cicd` 스킬 참조
- DB 설계/쿼리 최적화 시 → `rdb-optimization` 스킬 참조
