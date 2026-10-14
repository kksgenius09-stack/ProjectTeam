---
name: erp-spec-to-procedure
description: "Draft a SQL Server stored procedure for this team's multi-tenant ERP (DB 10.10.20.15:14233/EXSISMPDev) from a 화면설계 spec Excel. Use this whenever a teammate hands over a spec workbook (sheet 1 = 프로세스, sheet 2 = 화면설계서) and asks for a query/프로시저/조회 화면 to be built or extended — including requests phrased as '이 스펙대로 프로시저 만들어줘', '~조회(통합) 화면 작업', 'ㅇㅇ프로시저에 다이나믹컬럼 추가해줘', or just a spec file path dropped into chat with no further explanation. Also use it when asked to extend an existing procedure with new search conditions or a 다이나믹시트(다이나믹 컬럼). Do not use for one-off ad-hoc SELECT queries against the DB that aren't tied to a screen spec."
---

# ERP 스펙 → 프로시저 초안 생성

이 팀의 ERP는 여러 회사(EXSIS/TEMC CNS/FST 등)가 `CompanySeq`로 구분되어 한 DB(`10.10.20.15:14233` / `EXSISMPDev`)를 같이 쓰는 멀티테넌트 구조다. 신규/확장 화면마다 스펙 엑셀을 받아 SQL Server 저장 프로시저 초안을 만드는 게 반복 작업이고, 이 스킬은 그 과정에서 실제로 여러 번 틀려본 끝에 정리된 절차다.

**컨벤션 문서는 Notion에 계속 쌓이고 있다 — 이 스킬의 캐시가 아니라 Notion이 진실 공급원(source of truth)이다.** 작업을 시작할 때마다 반드시 먼저 읽는다:

> https://app.notion.com/p/3f8ab591e83e81bdb071e5eee9172708
> ("수출매출품목조회 확장 컨벤션 (관리번호 · 다이나믹컬럼)")

이 페이지는 팀원이 계속 규칙을 추가하는 살아있는 문서다. 여기 적힌 규칙과 이 SKILL.md가 어긋나면 **Notion 쪽을 따른다.**

## DB 접속 원칙 — 절대 쓰기 금지

이 작업 내내 DB는 **읽기 전용**으로만 다룬다. `SELECT`/`DESCRIBE`/`OBJECT_DEFINITION()` 외에는 DB에 아무것도 실행하지 않는다 — `CREATE PROCEDURE`도 DB에 직접 만들지 않고, 결과물은 항상 로컬 `.sql` 파일로만 저장한다. 이건 권한 문제가 아니라 원칙이다: 검증 안 된 초안을 실수로 실제 DB에 생성해버리는 사고를 구조적으로 막기 위함이다. 사용자가 "이제 개발계에 반영해도 돼"라고 명시적으로 말하기 전까지는 쓰기 작업을 제안조차 하지 않는다.

## 전체 흐름

### 0. 컨벤션 문서 읽기
위 Notion 페이지를 `notion-fetch`로 읽는다. 매번 최신 내용이 추가되어 있을 수 있으니(새 규칙, 새 레퍼런스 파일 등) 세션 시작 시점에 한 번은 반드시 다시 읽는다 — 전에 읽은 기억에 의존하지 않는다.

### 1. 스펙 엑셀 읽기
스펙 엑셀은 보통 이런 시트 구성이다: 1번 시트=프로세스 설명(업무 흐름, 도식), 2번 시트=화면설계서(화면개요, 조회조건/마스터, 시트(SS1) 등 항목 정의). 둘 다 읽으면 대부분의 요구사항을 알 수 있다. `openpyxl`로 읽되, 이 셀들은 텍스트 모양으로 레이아웃을 흉내낸 "그림" 성격이 강해서 셀 좌표+값을 그대로 덤프해서 훑어보는 게 빠르다(서식/병합을 해석하려 하지 않는다). `openpyxl`이 설치 안 되어 있으면 `pip install openpyxl`부터 한다 — 이 환경엔 기본 설치가 안 되어 있다.

**화면개요 문단을 가장 꼼꼼히 읽는다.** "표준 [X] 화면 그대로 사용함", "Y를 [통합조회] 로직으로 확장한다" 같은 한두 문장에 이 작업의 범위가 정확히 정의되어 있는 경우가 많다 — 나머지는 전부 그 범위 안에서의 세부사항이다.

### 2. 레퍼런스(베이스) 프로시저 확보 — 가장 중요한 규칙
**스키마만 보고 추측해서 조인을 새로 짜지 않는다.** 코드값(예: 작업장 구분 코드가 사내/외주 중 뭔지), 키 조인 경로, 원천조회 설정 같은 건 스키마만 봐서는 100% 확정할 수 없고, 추측하면 거의 항상 틀린다 — 실제로 이 작업에서 사내/외주 구분 로직을 스키마만 보고 짰다가 완전히 다른 베이스 프로시저를 썼어야 했던 적이 있다.

- 사용자가 베이스/레퍼런스 프로시저명을 이미 줬으면 그걸 쓴다.
- 안 줬으면 화면명/업무 키워드로 `sys.procedures`를 검색해서(예: `WHERE name LIKE '%WorkOrder%'`) 후보를 찾고, 가능성 높은 것부터 사용자에게 "이거 맞나요?"라고 확인받는다. 이름이 비슷한 게 여러 개면(`...ListQuery` vs `...TotalListQuery` 등) 전부 후보로 제시한다 — "List"가 단일 사내 버전이고 "TotalList"가 이미 통합 버전인 경우가 실제로 있었다.
- 후보를 찾았으면 `SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.프로시저명'))`로 전체 소스를 가져온다. 결과가 매우 길면(수백~천 줄) 한 번에 못 읽힐 수 있으니, 결과를 파일로 저장한 뒤 chunk로 나눠 읽는다.
- **사용자가 "이건 이미 만들어진 완성본이니 참고하지 마라"고 명시하면, 그 프로시저의 이름 검색도 내용 열람도 절대 하지 않는다.** 이건 보통 "정답을 안 보고 혼자 해보는 테스트"를 의도한 것이다.

### 3. 베이스를 보존하는 원칙
베이스 프로시저의 **조회조건(파라미터 선언부/WHERE절)과 전체 로직은 그대로 둔다.** 스펙이 요구하는 확장은 원칙적으로 SELECT절과 JOIN에서만 한다. 새 조회조건이 필요하면(스펙에 "조회조건 추가: X" 라고 적혀있으면) 파라미터를 추가하는 건 괜찮지만, 반드시 베이스가 쓰는 표준 골격을 따른다:

```sql
CREATE OR ALTER PROCEDURE [dbo].[프로시저명]
    @ServiceSeq     INT     = 0,
    @WorkingTag     NVARCHAR(10)= '',
    @CompanySeq     INT     = 1,
    @LanguageSeq    INT     = 1,
    @UserSeq        INT     = 0,
    @PgmSeq         INT     = 0,
    @IsTransaction  BIT     = 0
AS
    DECLARE @새파라미터 INT  -- ...
    SELECT  @새파라미터 = ISNULL(새파라미터, 0), ...
      FROM  #BIZ_IN_DataBlock1   -- 조회조건은 여기서 읽어온다 (직접 값을 박지 않는다)
```

베이스가 이미 어떤 기능(예: 사내/외주 통합, 관리번호 원천조회, 확정/중단 처리)을 구현하고 있다면 그건 건드리지 않는다 — 스펙에 "~로 확장한다"고만 적혀있어도, 그 기능이 베이스에 이미 있는지 먼저 확인하고 없을 때만 새로 짠다. (실제 사례: "사내+외주 통합"과 "관리번호 표시" 둘 다 베이스에 이미 구현되어 있어서 손댈 게 없었던 적이 있다.)

### 4. SQL 작성 가이드 (여러 개발자가 같이 보는 코드이므로)
- 질의어(SELECT/FROM/JOIN 등)는 대문자, Tab = 4 Space
- 테이블 별칭은 약자로 (`_TDAEmp` → `E`, `_TPDSFCWorkOrder` → `O` 등 — 베이스 코드에서 이미 쓰는 별칭 체계를 그대로 따르는 게 제일 안전하다)
- 조회용 SP는 테이블마다 `WITH(NOLOCK)` — 조회 전용이라 락 경합을 피하기 위함
- `INNER JOIN` 조건은 WHERE절이 아니라 해당 JOIN 바로 아래에 쓴다
- `ON`절은 새로 조인하는 테이블의 키 컬럼 순서대로 쓴다(인덱스/조회 속도 차이가 큼)
- `GROUP BY`는 필요한 최소 컬럼만

### 5. 다이나믹시트(다이나믹 컬럼)가 필요하면
화면설계서에 "시트(SS1)" 같은 섹션이 있거나, 화면개요에 "추가정보"/"기타분류"/"통합정보"/"다이나믹" 같은 단어가 있으면 이 패턴이다. 자세한 구조와 실제 코드 템플릿은 **`references/dynamic-sheet-pattern.md`를 반드시 읽고** 그대로 따른다 — 이 패턴은 "메타+값 두 결과집합으로 나누기" 같은 직관적인 방식이 아니라, 정확히 3개의 결과집합(컬럼정의/그리드/RowIDX×ColIDX 매트릭스)만 반환하는 이 회사 고유의 표준이라 틀리기 쉽다. 실제로 이 표준을 모르고 처음엔 4~5개 결과집합으로 잘못 만든 적이 있다.

핵심만 미리 말하면: 그룹(거래처/품목/자재 등, 각각 추가정보+기타분류)이 몇 개든 전부 **하나의** 컬럼정의 테이블과 **하나의** 값매트릭스에 `TitleSeq`로 구분해서 `UNION ALL`로 합친다 — 그룹마다 결과집합을 따로 만들지 않는다.

### 6. 관리번호 / 진행조회·원천조회가 필요하면
전표성 데이터(수주→매출→세금계산서, 구매요청→발주→납품→입고 같은 연결고리)에서 관리번호를 뽑아야 하면, `_SWCOMSourceTracking`(원천조회)/`_SWCOMProgressTracking`(진행조회) + `_TCOMProgTable`(설정 메타) 조합을 매번 새로 설계하지 말고, 베이스 프로시저가 이미 쓰고 있는 호출 패턴을 그대로 복사한다. 베이스가 `@SourceTableSeq` 같은 파라미터로 이미 범용 처리를 하고 있다면 그게 바로 "관리번호 표시" 요구사항을 충족하는 것일 수 있다 — 추가 작업 없이 넘어가도 되는지부터 확인한다.

### 7. 모든 가정은 실데이터로 검증한다
코드값의 의미, 매직넘버(예: 품목 분류단위 코드), 플래그 값 같은 건 절대 추측하지 않는다. 읽기 전용 `SELECT`로 직접 확인한다:

```sql
-- 코드값 추측 대신 실데이터 분포로 확인
SELECT SMWorkCenterType, COUNT(*), SUM(CASE WHEN CustSeq>0 THEN 1 ELSE 0 END)
  FROM _TPDBaseWorkCenter WHERE CompanySeq=1 GROUP BY SMWorkCenterType

-- 매직넘버 추측 대신 DISTINCT로 확인
SELECT DISTINCT DefineUnitSeq FROM _TCOMUserDefine WHERE TableName = '_TDAItem'
```
결과가 모호하면(예: 코드가 하나뿐이라 구분이 안 되면) 추측하지 말고 TODO로 남기고 사용자에게 물어본다. "그럴듯해 보인다"는 이유로 확정하지 않는다 — 이전에 그렇게 했다가 완전히 틀린 적이 있다.

### 8. 결과물 저장
- 파일명/프로시저명은 `_SW{모듈}{상세명}_TEST` 형태로 (예: `_SWPDSFCWorkOrderIntegratedListQuery_TEST`), 로컬 `.sql` 파일로 저장한다. 실제 배포용 프로시저명과 겹치지 않게 `_TEST` 접미사를 반드시 붙인다.
- 파일 상단 주석에 반드시 포함: 베이스 프로시저명, 스펙 파일 경로, 베이스 대비 추가/변경한 부분 목록, 확정 못하고 남긴 TODO. 나중에 다른 사람(또는 다음 세션의 나 자신)이 이 파일만 보고 무엇을 가정했는지 알 수 있어야 한다.
- 작업 중 틀려서 다시 만든 경우, 이전 시도가 왜 틀렸는지도 짧게 남긴다 — 같은 실수를 반복하지 않기 위함이다.
- 이 프로시저는 **실행해보지 않은 상태**라는 걸 사용자에게 분명히 알린다. 읽기 전용 연결로는 `CREATE PROCEDURE`/`EXEC` 자체가 불가능하므로, 문법 오류나 조인 결과가 실제로 맞는지는 개발계에서 직접 돌려봐야 확인된다.
