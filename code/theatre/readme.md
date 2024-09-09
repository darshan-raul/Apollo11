# Setup

## Database setup

- in docker-compose there is a mongodb database
    - you can start it using `docker compose up -d`

Note: if you have to ever change the password in docker-compose you will have to delete the volume as the initdb thing only runs once when the db is created
https://github.com/docker-library/mongo/issues/174#issuecomment-297538188