---
name: async-patterns
description: Async/await and Promise patterns
metadata:
  tags: async, await, promises, concurrency
---

# Async Patterns in Node.js

## Always Prefer async/await

Use async/await over raw Promises for readability:

```typescript
// GOOD
async function processItems(items: Item[]): Promise<Result[]> {
  const results: Result[] = [];
  for (const item of items) {
    const result = await processItem(item);
    results.push(result);
  }
  return results;
}
```

## Parallel Execution with Promise.all

Use Promise.all for independent operations:

```typescript
async function fetchAllData(ids: string[]): Promise<Data[]> {
  const promises = ids.map((id) => fetchData(id));
  return Promise.all(promises);
}
```

## Controlled Concurrency

Limit concurrent operations to prevent resource exhaustion. Use [p-limit](https://github.com/sindresorhus/p-limit) or [p-map](https://github.com/sindresorhus/p-map):

```typescript
import pLimit from 'p-limit';

const limit = pLimit(5); // Max 5 concurrent operations

const results = await Promise.all(
  items.map((item) => limit(() => processItem(item)))
);
```

## Promise.allSettled for Fault Tolerance

Use Promise.allSettled when some failures are acceptable:

```typescript
async function fetchMultiple(urls: string[]): Promise<Map<string, string | Error>> {
  const results = await Promise.allSettled(
    urls.map((url) => fetch(url).then((r) => r.text()))
  );
  const map = new Map<string, string | Error>();
  urls.forEach((url, i) => {
    const result = results[i];
    map.set(url, result.status === 'fulfilled' ? result.value : result.reason);
  });
  return map;
}
```

## Avoid Async in Constructors

Use factory functions instead:

```typescript
class Database {
  private constructor(private connection: Connection) {}

  static async create(config: Config): Promise<Database> {
    const connection = await connect(config);
    return new Database(connection);
  }
}

const db = await Database.create(config);
```

## AbortController for Cancellation

```typescript
async function fetchWithTimeout(url: string, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
  }
}
```
