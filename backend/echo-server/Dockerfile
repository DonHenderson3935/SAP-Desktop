FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o echo-server .

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /app/echo-server /echo-server

EXPOSE 8080

ENTRYPOINT ["/echo-server"]
