# 에러 핸들링 상세

## 도메인 에러 계층 구조

```typescript
// Base Error
export abstract class AppError extends Error {
  abstract readonly statusCode: number;
  abstract readonly code: string;
  readonly isOperational: boolean;

  constructor(message: string, isOperational = true) {
    super(message);
    this.name = this.constructor.name;
    this.isOperational = isOperational;
    Error.captureStackTrace(this, this.constructor);
  }

  toJSON() {
    return {
      error: {
        code: this.code,
        message: this.message,
      },
    };
  }
}

// 구체 에러 클래스
export class NotFoundError extends AppError {
  readonly statusCode = 404;
  readonly code = 'NOT_FOUND';
  constructor(resource: string, id: string) {
    super(`${resource} with id '${id}' not found`);
  }
}

export class ValidationError extends AppError {
  readonly statusCode = 422;
  readonly code = 'VALIDATION_ERROR';
  constructor(
    message: string,
    public readonly details: { field: string; reason: string }[]
  ) {
    super(message);
  }

  toJSON() {
    return {
      error: {
        code: this.code,
        message: this.message,
        details: this.details,
      },
    };
  }
}

export class ConflictError extends AppError {
  readonly statusCode = 409;
  readonly code = 'CONFLICT';
}

export class UnauthorizedError extends AppError {
  readonly statusCode = 401;
  readonly code = 'UNAUTHORIZED';
}

export class ForbiddenError extends AppError {
  readonly statusCode = 403;
  readonly code = 'FORBIDDEN';
}

export class ExternalServiceError extends AppError {
  readonly statusCode = 502;
  readonly code = 'EXTERNAL_SERVICE_ERROR';
  constructor(service: string, originalError: Error) {
    super(`External service '${service}' failed: ${originalError.message}`, true);
  }
}
```

---

## HTTP 에러 핸들러 (Express/NestJS)

### Express Global Error Handler
```typescript
function errorHandler(err: Error, req: Request, res: Response, next: NextFunction) {
  // 운영 에러 (예상된 에러)
  if (err instanceof AppError) {
    return res.status(err.statusCode).json(err.toJSON());
  }

  // 프로그래밍 에러 (예상치 못한 에러)
  console.error('Unexpected error:', err);
  return res.status(500).json({
    error: {
      code: 'INTERNAL_ERROR',
      message: 'An unexpected error occurred',
    },
  });
}

app.use(errorHandler);
```

### NestJS Exception Filter
```typescript
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    if (exception instanceof AppError) {
      return response.status(exception.statusCode).json(exception.toJSON());
    }

    if (exception instanceof HttpException) {
      return response.status(exception.getStatus()).json(exception.getResponse());
    }

    console.error('Unhandled exception:', exception);
    return response.status(500).json({
      error: { code: 'INTERNAL_ERROR', message: 'An unexpected error occurred' },
    });
  }
}
```

---

## Result 패턴 (neverthrow)

```typescript
import { Result, ok, err } from 'neverthrow';

// throw 대신 Result 반환
function parseEmail(input: string): Result<Email, ValidationError> {
  if (!input.includes('@')) {
    return err(new ValidationError('Invalid email', [{ field: 'email', reason: 'format' }]));
  }
  return ok(new Email(input));
}

// 체이닝
async function createUser(dto: CreateUserDto): Promise<Result<User, AppError>> {
  return parseEmail(dto.email)
    .andThen(email => validatePassword(dto.password).map(pw => ({ email, pw })))
    .asyncAndThen(async ({ email, pw }) => {
      const exists = await userRepo.findByEmail(email);
      if (exists) return err(new ConflictError('Email already registered'));
      return ok(await userRepo.create({ email, password: pw }));
    });
}

// Controller에서 사용
async function handler(req: Request, res: Response) {
  const result = await createUser(req.body);
  result.match(
    user => res.status(201).json({ data: user }),
    error => res.status(error.statusCode).json(error.toJSON())
  );
}
```

---

## 글로벌 핸들러

```typescript
// unhandledRejection: Promise reject가 catch되지 않은 경우
process.on('unhandledRejection', (reason: unknown) => {
  console.error('Unhandled Rejection:', reason);
  // 로깅 후 graceful shutdown
  // 프로덕션에서는 프로세스 재시작 권장 (PM2/K8s가 처리)
});

// uncaughtException: 동기 코드에서 catch되지 않은 에러
process.on('uncaughtException', (error: Error) => {
  console.error('Uncaught Exception:', error);
  // 상태가 불확실하므로 반드시 프로세스 종료
  process.exit(1);
});
```

---

## 외부 서비스 에러 래핑

```typescript
class PaymentGateway {
  async charge(amount: number, token: string): Promise<Result<PaymentResult, AppError>> {
    try {
      const response = await this.httpClient.post('/charge', { amount, token });
      return ok(response.data);
    } catch (error) {
      if (error instanceof AxiosError) {
        if (error.response?.status === 402) {
          return err(new ValidationError('Payment declined', [
            { field: 'card', reason: 'insufficient_funds' }
          ]));
        }
        if (error.code === 'ECONNABORTED') {
          return err(new ExternalServiceError('payment-gateway', error));
        }
      }
      return err(new ExternalServiceError('payment-gateway', error as Error));
    }
  }
}
```

---

## 에러 로깅 전략

```typescript
// 에러 심각도별 로깅
function logError(error: Error, context?: object) {
  const payload = {
    name: error.name,
    message: error.message,
    stack: error.stack,
    ...context,
    timestamp: new Date().toISOString(),
  };

  if (error instanceof AppError && error.isOperational) {
    // 운영 에러: warn 레벨 (예상된 상황)
    logger.warn(payload);
  } else {
    // 프로그래밍 에러: error 레벨 (즉시 대응 필요)
    logger.error(payload);
    // 알림 발송 (Slack, PagerDuty 등)
    alertService.notify(payload);
  }
}
```
