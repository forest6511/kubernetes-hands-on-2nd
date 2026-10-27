# todo-api のイメージ。ビルド用と実行用の2段階に分け、実行用には完成したプログラムだけを入れる
FROM golang:1.27.3-alpine@sha256:b8c9b82affbbb82a020bbcf998dad2ba9516944ac7e883524642a481a9505e9c AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /todo-api .

FROM alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a
COPY --from=build /todo-api /usr/local/bin/todo-api
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/todo-api"]
