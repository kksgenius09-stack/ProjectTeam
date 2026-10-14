# ProjectTeam - Claude Code 공유 스킬

ERP 개발팀이 공용으로 쓰는 Claude Code 스킬 모음입니다.

## 포함된 스킬

- `skills/erp-spec-to-procedure` — 화면설계 스펙 엑셀을 읽고 EXSIS ERP(DB `10.10.20.15:14233/EXSISMPDev`) 스토어드 프로시저를 작성/확장하는 스킬. 다이나믹컬럼(다이나믹시트) 패턴 포함.

## 최초 설치 (팀원)

1. 이 저장소를 로컬에 clone 합니다.
   ```
   git clone https://github.com/kksgenius09-stack/ProjectTeam.git
   ```
2. clone된 폴더에서 `install-skills.bat`을 더블클릭(또는 실행)합니다.
   - `skills/` 아래 각 스킬을 `%USERPROFILE%\.claude\skills\` 밑에 자동으로 연결(junction)해줍니다.
   - 관리자 권한이 필요 없습니다.

## 업데이트 받기

스킬 내용이 바뀌면, clone해둔 폴더에서 아래만 실행하면 됩니다.

```
git pull
```

연결이 junction이라 별도 재설치 없이 바로 최신 내용이 반영됩니다.

## 스킬 수정 후 반영 (작성자용)

1. `skills/<스킬이름>/` 아래 파일을 수정
2. 커밋 후 push
   ```
   git add -A
   git commit -m "update skill"
   git push
   ```
