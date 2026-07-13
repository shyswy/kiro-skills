---
name: error-handling
description: Error handling patterns in Node.js
metadata:
  tags: errors, exceptions, try-catch, error-handling
---

# Error Handling in Node.js

## Custom Error Pattern

Use a minimal factory pattern for creating custom errors with codes:

```typescript
interface AppErrorOptions {
  code: string;
  statusCode?: number;
  cause?: Error;
}

function createAppError(message: string, options: AppErrorOptions): Error {
  const error = new Error(message, { cause: options.cause });
  (error as any).code = options.code;
  (error as any).statusCode = options.statusCode ?? 500;
  Error.captureStackTrace(error, createAppError);
  return error;
}

// Factory functions for common errors
function notFound(resource: string): Error {
  return createAppError(`${resource} not found`, { code: 'NOT_FOUND', statusCode: 404 });
}

function validationError(message: string): Error {
  return createAppError(message, { code: 'VALIDATION_ERROR', statusCode: 400 });
}

function databaseError(message: string, cause?: Error): Error {
  return createAppError(message, { code: 'DATABASE_ERROR', statusCode: 500, cause });
}
```

## Checking Error Codes

Check errors by code, not by class:

```typescript
function isAppError(error: unknown): error is Error & { code: string; statusCode: number } {
  return error instanceof Error && 'code' in error && 'statusCode' in error;
}

try {
  await fetchUser(id);
} catch (error) {
  if (isAppError(error) && error.code === 'NOT_FOUND') {
    return null;
  }
  throw error;
}
```

## Async Error Handling

Always use try-catch with async/await and propagate errors properly:

```typescript
async function fetchUser(id: string): Promise<User> {
  try {
    const user = await db.users.findById(id);
    if (!user) {
      throw notFound('User');
    }
    return user;
  } catch (error) {
    if (isAppError(error)) {
      throw error;
    }
    throw databaseError('Failed to fetch user', error as Error);
  }
}
```

## Unhandled Rejections and Exceptions

Do not handle `unhandledRejection` and `uncaughtException` manually. Use [close-with-grace](https://github.com/fastify/close-with-grace) which handles these automatically and triggers graceful shutdown.

See [graceful-shutdown.md](./graceful-shutdown.md) for proper shutdown handling.

## Never Swallow Errors

Never use empty catch blocks that hide errors:

```typescript
// BAD - error is swallowed
try {
  await riskyOperation();
} catch (error) {
  // Do nothing
}

// GOOD - handle or re-throw
try {
  await riskyOperation();
} catch (error) {
  logger.error({ err: error }, 'Operation failed');
  throw error;
}
```

## Error Cause Chain

Use the `cause` option to preserve error chains:

```typescript
try {
  await externalService.call();
} catch (error) {
  throw new Error('Service call failed', { cause: error });
}
```
