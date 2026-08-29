# sns-app 은 Jib 으로 Dockerfile 없이 이미지를 만들지만, Jib 은 Java 전용이다.
# Go 는 멀티스테이지 빌드로 정적 바이너리 하나만 남긴다.
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/recommender .

# 정적 바이너리라 셸도 패키지 매니저도 필요 없다. 최종 이미지는 약 16MB 다.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/recommender /recommender
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/recommender"]
