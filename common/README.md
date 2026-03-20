# notes

## helm

```bash
git clone https://github.com/helm/helm.git
cd helm
make
```

## mongodb on docker

```bash
# NOTE: Replace <MONGO_INITDB_ROOT_USERNAME> and <MONGO_INITDB_ROOT_PASSWORD>
# with your own secure credentials. These values are intended for local
# development only and MUST NOT be reused in production.
docker run --name mongodb \
  -d \
  -p 27017:27017 \
  -v mongodb-data:/data/db \
  -e MONGO_INITDB_ROOT_USERNAME=<MONGO_INITDB_ROOT_USERNAME> \
  -e MONGO_INITDB_ROOT_PASSWORD=<MONGO_INITDB_ROOT_PASSWORD> \
  mongo
```

```bash
# connection string (match the username/password you configured above)
mongodb://<MONGO_INITDB_ROOT_USERNAME>:<MONGO_INITDB_ROOT_PASSWORD>@localhost:27017

# stop
docker stop mongodb

# start
docker start mongodb

# logs
docker logs -f mongodb
```
