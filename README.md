# Quad

### Example

```yaml
apiVersion: v1
experiment:
- tag: server
  image: vitorenesduarte/server
  replicas: 3
  workflow:
    end:
      name: client-b_end
      value: 6
- tag: client-a
  image: vitorenesduarte/client
  replicas: 3
  env:
  - name: OPS
    value: 100
  workflow:
    start:
      name: server-ready
      value: 3
- tag: client-b
  image: vitorenesduarte/client
  replicas: 6
  env:
  - name: OPS
    value: 200
  workflow:
    start:
      name: client-b_end
      value: 3
```
