# z2roN_story (메일챗)

POP3 / IMAP 메일을 메신저처럼 보여주고, 입력하면 SMTP로 바로 답장하는 Windows·Android 앱 (Flutter).

## 동작
- 앱 암호: 처음 실행 때 암호를 만들면 계정 정보(메일 비밀번호 포함)와 대화 내용이 AES-256-GCM으로 암호화되어 저장됨
  (암호 → PBKDF2-SHA256 10만 회로 키 유도). 아이디 없이 암호만 사용
- 자동 로그인: 켜면 키를 OS 보안 저장소(Windows DPAPI / Android Keystore)에 보관해 다음 실행부터 암호 입력 생략.
  메뉴의 "잠금(로그아웃)"을 누르면 자동 로그인이 해제되고 다시 암호를 묻는다. 암호를 잊으면 데이터를 초기화해야 함(복구 불가)
- 메일 계정 최대 10개 (IMAP 또는 POP3 + SMTP)
- 메인 화면: 메일 제목 목록. "계정별"(계정마다 묶음, 계정 색상 표시) / "전체(최신순)" 전환, 검색
- 제목을 누르면 메신저 대화방: 받은 메일은 왼쪽, 내가 보낸 메일은 오른쪽 말풍선 (인용문·서명 자동 제거)
- 입력 후 전송 → SMTP 발송 (`Re:` 제목, `In-Reply-To`/`References` 헤더로 상대 메일함에서도 같은 대화로 묶임)
- 파일 첨부: + 버튼으로 여러 개 선택해 전송(합계 20MB), 받은 첨부는 앱 폴더에 저장, 이미지는 미리보기, 눌러서 열기
- 60초마다 자동 새로고침, 앱을 다시 열 때도 새로고침
- IMAP: 받은편지함 + 보낸편지함 / POP3: UIDL로 새 메일만 가져옴 (서버 메일 삭제 안 함)
- Windows: Enter 전송, Shift+Enter 줄바꿈. 시스템 설정에 따라 라이트/다크 모드 자동 적용
- 화면: 파랑 그라데이션 헤더 + 작은 버튼 + 카드 레이아웃. 처음 실행 시 Gmail/네이버/다음 중 골라 바로 계정 추가(서버 설정은 자동 입력)
- HTML로 작성된 메일은 HTML로 표시(원격 이미지는 기본 차단, 눌러서 보기). 읽은 메일은 신규(N) 표시가 사라지고, 메뉴에 "모두 읽음"이 있음
- 버전 표시: 메인 화면 제목 옆/메뉴 "버전 정보"에서 현재 버전과 업데이트 내역 확인 (업데이트할 때마다 `pubspec.yaml`의 version과 `lib/version.dart`를 함께 올림)
- 앱 아이콘(메일챗)은 `assets/icon/`의 PNG에서 빌드 시 자동 생성

## 빌드 방법
### A) GitHub Actions (권장, 로컬 설치 불필요)
이 폴더를 GitHub 저장소에 올리고 Actions > build > Run workflow. 끝나면 Artifacts에서
`z2roN_story-android-v버전`(APK), `z2roN_story-windows-v버전`(Windows 폴더, z2roN_story.exe)를 받습니다.

### B) 내 PC에서
Flutter SDK 설치 후 이 폴더에서:
```
flutter create --platforms=android,windows --project-name z2ron_story --org com.z2ron .
flutter pub get
dart run flutter_launcher_icons
flutter build windows --release     # build/windows/x64/runner/Release/ (실행 파일: z2roN_story.exe 로 이름을 바꾸려면 windows/CMakeLists.txt 의 BINARY_NAME 수정)
flutter build apk --release         # build/app/outputs/flutter-apk/app-release.apk
```
Android는 `android/app/build.gradle(.kts)`의 minSdk를 23 이상으로 올리고(보안 저장소 요구), `android/app/src/main/AndroidManifest.xml`의 `<application` 앞에
`<uses-permission android:name="android.permission.INTERNET"/>` 한 줄을 추가해야 릴리스 빌드에서 인터넷이 됩니다.

## 알아둘 점
- Gmail은 앱 비밀번호, 네이버/다음은 설정에서 POP3/IMAP 사용을 켜야 합니다.
- POP3는 보낸편지함이 없어서, 이 앱에서 보낸 메일만 오른쪽 말풍선으로 보입니다.
- 암호화 대상은 계정 정보와 대화 텍스트입니다. 받은/보낸 첨부파일 사본은 앱 폴더에 암호화 없이 저장됩니다.
- Android 백그라운드 알림은 아직 없고, 앱을 열어둔 동안만 자동 수신합니다.

## Android 빌드가 실패할 때
Actions > 실패한 실행 > 빨간 X 단계를 열어 마지막 30줄 정도의 오류 메시지를 확인하세요.
워크플로는 보안 저장소 요구사항(minSdk 23)과 R8 오류 방지(`--no-shrink`)를 이미 적용해 둡니다.

## Gmail이 연결되지 않을 때
Gmail은 일반 비밀번호로는 연결되지 않습니다.
1. Google 계정 > 보안 > 2단계 인증 켜기
2. "앱 비밀번호"(https://myaccount.google.com/apppasswords) 만들기 → 16자리 코드를 비밀번호 칸에 입력 (공백은 자동 제거)
3. Gmail > 설정 > 전달 및 POP/IMAP에서 IMAP 사용 켜기 (IMAP 권장)
계정 추가 화면의 [연결 테스트]를 누르면 실패 원인이 한글로 안내됩니다. 회사/학교(Google Workspace) 계정은 관리자가 막아 두면 연결되지 않을 수 있습니다.

## 버전 기록
업데이트할 때마다 `pubspec.yaml`의 version, `lib/version.dart`의 업데이트 내역, `CHANGELOG.md`를 함께 갱신합니다.
