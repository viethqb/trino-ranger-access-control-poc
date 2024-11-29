# Trino 466 - Ranger Access Control 

## Start Ranger

```bash
docker compose up postgres -d
docker compose up opensearch -d
docker compose up ranger -d

# http://localhost:6080
# User: admin
# Password: rangerR0cks!
```

## Start trino 
```bash
docker compose up -d
```