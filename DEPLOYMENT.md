# 여행벌이 API 배포

Java 25 / Spring Boot 4.1 프로젝트를 GHCR에 저장하고 물리 서버의 독립 Compose 프로젝트 `travel-job`으로 배포한다. Next.js는 Vercel에서 별도로 배포한다.

## GitHub Actions

master PR: PostgreSQL 테스트 DB와 함께 Gradle build/test.
master push 또는 master에서 수동 실행: 테스트 → SHA 이미지 업로드 → production 환경 SSH 배포 → HTTP/DB health 확인.

GitHub 저장소 Settings → Secrets and variables → Actions에 등록:

| Secret | 값 |
|---|---|
| SERVER_HOST | 배포 서버 주소 |
| SERVER_PORT | SSH 포트 |
| SERVER_USER | Docker 사용 권한이 있는 배포 사용자 |
| SERVER_PATH | 여행벌이 전용 절대 경로. 예: /opt/travel-job (공백 없이) |
| SSH_PRIVATE_KEY | 해당 배포 계정의 SSH 개인키 |
| SSH_KNOWN_HOSTS | 검증한 서버의 known_hosts 항목. 비표준 포트는 [host]:port 형태 |

production Environment를 생성한다. 승인 규칙을 설정하면 배포 전에 승인받을 수 있다. GITHUB_TOKEN은 빌드 시 GHCR 업로드에 사용한다. 비공개 GHCR 이미지를 pull할 서버에는 별도의 read:packages 권한 토큰으로 `docker login ghcr.io`를 최초 1회 실행해야 한다. CI 토큰을 서버에 복사하지 않는다. 이미지는 현재 GitHub 러너 기본인 linux/amd64 대상이다. ARM 서버라면 대상 플랫폼을 변경해야 한다.

## 서버 최초 준비

Docker Engine 및 `docker compose up --wait`를 지원하는 Compose v2가 필요하다.

1. 전용 배포 경로를 만들고 `.env.example`을 참고해 `.env` 작성. `chmod 600 .env`.
2. 기존 PostgreSQL에 여행벌이 전용 DB와 최소 권한 계정을 생성.
3. DB 연결 전용 네트워크를 만들고 기존 DB 컨테이너를 연결:

```sh
docker network create travel-job-database
docker network connect --alias travel-job-postgres travel-job-database unimal-postgis
```

이는 운영 DB의 네트워크 설정을 바꾸는 작업이므로 운영자가 확인 후 수행한다. 재생성 시에도 유지되도록 **DB를 관리하는 Compose**에 이 external 네트워크를 추가해야 한다. 일회성 network connect만으로는 재배포 후 유지되지 않는다. 유니멀 앱 네트워크와 여행벌이 앱 네트워크는 공유하지 않는다. DB 접근만 별도 네트워크로 허용한다. DB는 Nginx를 거치지 않는다.

4. `.env`의 DATABASE_HOST=travel-job-postgres, DATABASE_PORT=5432 및 전용 DB/계정 설정.
5. GHCR 로그인 확인 후 Actions 실행.

현재 운영 프로필은 ddl-auto=validate, SQL 초기화 비활성화다. 엔티티 추가 시 DB 마이그레이션을 먼저 준비해야 한다. 로컬의 update/자동 SQL 초기화를 운영에 사용하지 않는다. 현재 프로젝트에는 JWT 코드가 없어 JWT 변수는 사용하지 않으며, 인증 구현 시 별도 설정한다.

## Nginx 연결

현재 유니멀 Nginx는 host 네트워크를 사용하므로 여행벌이 앱과 Docker 네트워크를 공유할 필요가 없다. API는 호스트 127.0.0.1:8090에만 바인딩한다. 운영 서버의 8090 포트 충돌을 먼저 확인한다.

기존 Nginx의 http 블록 안에 아래 server 구성을 **기존 인증서 경로에 맞춰** 추가한다. 기존 Nginx가 이미 80/443을 점유하므로 별도 Nginx를 같은 포트에 띄우지 않는다.

```nginx
server {
    listen 443 ssl;
    server_name api.traveljob.kr;
    # ssl_certificate /path/to/certificate.pem;
    # ssl_certificate_key /path/to/private-key.pem;
    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location /actuator/ { return 404; }
}
```

이 예시는 인증서 설정을 채운 뒤 사용한다. Nginx 설정 검사 후 reload, DNS/HTTPS 연결을 별도로 수행한다. Actions는 공용 Nginx나 DB를 수정하지 않는다. Vercel 프론트와 API의 CORS/로그인 설정은 인증 구현 시 명시적으로 구성해야 한다.

## 운영 명령 및 롤백

배포 디렉토리에서 `.env`에는 마지막 성공한 SHA가 기록된다.

```sh
docker compose -p travel-job ps
docker compose -p travel-job logs --tail=100 api
```

배포가 health 확인에 실패하면 Actions도 실패하지만 자동 롤백은 하지 않는다. 기존 SHA는 `.env`에 남아 있으므로 원인 확인 후 아래 명령으로 이전 성공 버전을 다시 올릴 수 있다. 최초 배포 실패 시에는 이전 버전이 없다.

```sh
docker compose -p travel-job up -d --no-deps --wait api
```

컨테이너 종료나 전역 prune은 배포 과정에서 수행하지 않는다. 공유 물리 서버 및 DB 자원 장애의 영향은 서로 받을 수 있다.
