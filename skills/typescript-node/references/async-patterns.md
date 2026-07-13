# 비동기 패턴 상세

## 동시성 제어

### Promise.all vs Promise.allSettled
```typescript
// 하나라도 실패하면 전체 실패 (all-or-nothing)
const results = await Promise.all([fetchUser(), fetchOrders(), fetchPayments()]);

// 실패해도 나머지 결과 수집 (partial success 허용)
const results = await Promise.allSettled([fetchUser(), fetchOrders(), fetchPayments()]);
results.forEach(r => {
  if (r.status === 'fulfilled') console.log(r.value);
  if (r.status === 'rejected') console.error(r.reason);
});
```

### 동시 실행 제한 (Concurrency Limiter)
```typescript
async function pMap<T, R>(
  items: T[],
  mapper: (item: T) => Promise<R>,
  concurrency: number
): Promise<R[]> {
  const results: R[] = [];
  const executing = new Set<Promise<void>>();

  for (const item of items) {
    const p = mapper(item).then(r => { results.push(r); });
    executing.add(p);
    p.finally(() => executing.delete(p));

    if (executing.size >= concurrency) {
      await Promise.race(executing);
    }
  }
  await Promise.all(executing);
  return results;
}

// 사용: 최대 5개 동시 실행
await pMap(urls, url => fetch(url), 5);
```

### Semaphore 패턴
```typescript
class Semaphore {
  private queue: (() => void)[] = [];
  private current = 0;

  constructor(private max: number) {}

  async acquire(): Promise<void> {
    if (this.current < this.max) {
      this.current++;
      return;
    }
    return new Promise(resolve => this.queue.push(resolve));
  }

  release(): void {
    this.current--;
    const next = this.queue.shift();
    if (next) { this.current++; next(); }
  }
}

const sem = new Semaphore(3);
async function limitedFetch(url: string) {
  await sem.acquire();
  try { return await fetch(url); }
  finally { sem.release(); }
}
```

---

## Backpressure 처리

### Readable Stream + Transform
```typescript
import { Transform, pipeline } from 'stream';
import { promisify } from 'util';

const pipelineAsync = promisify(pipeline);

const transform = new Transform({
  objectMode: true,
  highWaterMark: 100,  // 버퍼 크기 제한
  async transform(chunk, encoding, callback) {
    try {
      const result = await processItem(chunk);
      callback(null, result);
    } catch (err) {
      callback(err as Error);
    }
  }
});

await pipelineAsync(readableSource, transform, writableDest);
```

### AsyncGenerator + 배치 처리
```typescript
async function* batchProcess<T>(
  source: AsyncIterable<T>,
  batchSize: number
): AsyncGenerator<T[]> {
  let batch: T[] = [];
  for await (const item of source) {
    batch.push(item);
    if (batch.length >= batchSize) {
      yield batch;
      batch = [];
    }
  }
  if (batch.length > 0) yield batch;
}

// 사용
for await (const batch of batchProcess(kafkaMessages, 100)) {
  await bulkInsert(batch);  // 100개씩 배치 처리
}
```

---

## Graceful Shutdown

```typescript
class GracefulShutdown {
  private shutdownCallbacks: (() => Promise<void>)[] = [];
  private isShuttingDown = false;

  register(callback: () => Promise<void>): void {
    this.shutdownCallbacks.push(callback);
  }

  start(): void {
    const signals: NodeJS.Signals[] = ['SIGTERM', 'SIGINT'];
    signals.forEach(signal => {
      process.on(signal, () => this.shutdown(signal));
    });
  }

  private async shutdown(signal: string): Promise<void> {
    if (this.isShuttingDown) return;
    this.isShuttingDown = true;
    console.log(`Received ${signal}, shutting down gracefully...`);

    const timeout = setTimeout(() => {
      console.error('Forced shutdown after timeout');
      process.exit(1);
    }, 30000);

    for (const cb of this.shutdownCallbacks) {
      await cb();
    }
    clearTimeout(timeout);
    process.exit(0);
  }
}

// 사용
const shutdown = new GracefulShutdown();
shutdown.register(async () => { await server.close(); });
shutdown.register(async () => { await db.disconnect(); });
shutdown.register(async () => { await kafka.disconnect(); });
shutdown.start();
```

---

## Timeout / Cancellation

### AbortController
```typescript
async function fetchWithTimeout(url: string, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    return await fetch(url, { signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

// 여러 작업 취소
const controller = new AbortController();
const tasks = urls.map(url => fetch(url, { signal: controller.signal }));

setTimeout(() => controller.abort(), 5000);  // 5초 후 전체 취소
await Promise.allSettled(tasks);
```

### Retry with Exponential Backoff
```typescript
async function retry<T>(
  fn: () => Promise<T>,
  options: { maxRetries: number; baseDelay: number; maxDelay: number }
): Promise<T> {
  let lastError: Error;
  for (let attempt = 0; attempt <= options.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err as Error;
      if (attempt === options.maxRetries) break;

      const delay = Math.min(
        options.baseDelay * Math.pow(2, attempt) + Math.random() * 100,
        options.maxDelay
      );
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
  throw lastError!;
}

// 사용
const result = await retry(() => callExternalApi(), {
  maxRetries: 3, baseDelay: 1000, maxDelay: 10000
});
```

---

## AsyncLocalStorage (요청 컨텍스트)

```typescript
import { AsyncLocalStorage } from 'async_hooks';

interface RequestContext {
  requestId: string;
  userId?: string;
  startTime: number;
}

const asyncLocalStorage = new AsyncLocalStorage<RequestContext>();

// 미들웨어에서 컨텍스트 설정
function requestContextMiddleware(req: Request, res: Response, next: NextFunction) {
  const context: RequestContext = {
    requestId: req.headers['x-request-id'] as string || crypto.randomUUID(),
    userId: req.user?.id,
    startTime: Date.now(),
  };
  asyncLocalStorage.run(context, () => next());
}

// 어디서든 컨텍스트 접근 (prop drilling 없이)
function getRequestContext(): RequestContext | undefined {
  return asyncLocalStorage.getStore();
}

// 로거에서 활용
class Logger {
  info(message: string, meta?: object) {
    const ctx = getRequestContext();
    console.log(JSON.stringify({
      level: 'info', message, ...meta,
      requestId: ctx?.requestId,
      userId: ctx?.userId,
    }));
  }
}
```
