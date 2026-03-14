# notes

## helm

```bash
git clone https://github.com/helm/helm.git
cd helm
make
```

## mongodb on docker

```bash
docker run --name mongodb \
  -d \
  -p 27017:27017 \
  -v mongodb-data:/data/db \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin123 \
  mongo
```

```bash
# connection string
mongodb://admin:admin123@localhost:27017

# stop
docker stop mongodb

# start
docker stop mongodb

# logs
docker stop mongodb
```
