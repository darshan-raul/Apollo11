
- Run this commands to create local docker go image and then run the go commands from inside that container

    ```
    docker build --target dev . -t go
    docker run -it -v ${PWD}:/work go sh
    go version
    ```

- If you need to update the files locally and just run the go run command inside container, use:
     `docker run -it -v ${PWD}:/work go /bin/sh -c "cd app; go run app.go"`