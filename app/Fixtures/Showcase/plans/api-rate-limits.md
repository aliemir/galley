# API rate limits

Limits are per token, not per IP: a whole office behind one NAT is one IP.

## Current limits

| Tier | Requests / min | Burst |
|------|---------------:|------:|
| Free | 60 | 20 |
| Team | 600 | 120 |
| Enterprise | 6000 | 1000 |

## Proposal

Move to a token bucket refilled every second, so a burst is spent and earned
back smoothly instead of resetting on the minute.

```python
def allow(bucket, now):
    bucket.tokens = min(bucket.capacity, bucket.tokens + (now - bucket.last) * bucket.rate)
    bucket.last = now
    if bucket.tokens >= 1:
        bucket.tokens -= 1
        return True
    return False
```

> [!IMPORTANT]
> Enterprise customers have limits written into their contracts. Any change
> needs sign-off from sales before it ships.
