FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go mod init go-service && \
    go build -o service main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates wget
WORKDIR /root/
COPY --from=builder /app/service .
EXPOSE 8080
CMD ["./service"]
