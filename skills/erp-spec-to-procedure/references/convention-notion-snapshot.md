# 📐 수출매출품목조회 확장 컨벤션 (관리번호 · 다이나믹컬럼)

> 이 파일은 Notion 페이지(https://app.notion.com/p/3f8ab591e83e81bdb071e5eee9172708)를
> **2026-10-13 기준**으로 스냅샷떠서 git에 넣은 버전입니다. 원본 Notion 페이지가 더 최신일 수 있습니다 —
> 규칙이 바뀌면 이 파일도 다시 동기화해야 합니다(관리자: kks95). 첨부된 .sql/.pptx/.xlsx 원본 파일은
> 이 스냅샷에 포함되지 않았으니, 실제 예시 코드 패턴은 같은 폴더의 `dynamic-sheet-pattern.md`를 참고하세요.

이 문서는 "수출매출품목조회" 화면에 관리번호 3컬럼과 거래처/품목/자재 다이나믹컬럼을 추가하면서 정리한 **이 ERP의 공통 패턴**입니다. 비슷한 화면(진행조회/원천조회, 추가정보/기타분류 다이나믹시트)을 새로 만들 때 이 문서를 먼저 참고하세요.

# 0. 가장 중요한 규칙

- **기존 조회조건(파라미터 선언부/WHERE절)은 그대로 둔다.** 컬럼 추가/로직 확장은 SELECT 절과 JOIN에서만 한다.
- **신규/확장 화면 작업 시, 스키마만 보고 추측하지 말고 먼저 비슷한 기존 프로시저(베이스/레퍼런스)를 찾아서 제공한다.** 컬럼의 실제 의미(코드값, 날짜 기준, 조인 경로 등)는 DB 스키마만으로는 100% 확정할 수 없고, 이미 검증된 레퍼런스 프로시저가 있으면 추측 TODO를 대부분 없앨 수 있다.
- 일반 조회하면 혹은 생성 프로시저에서 다른 프로시저를 호출하는 프로시저를 호출프로시저라고 한다
- 일반 프로시저는 아래로 규칙으로 생성한다

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
        --변수
    DECLARE @BizUnit        INT,
            @SalesDateFr    NCHAR(8),
            @SalesDateTo    NCHAR(8),
            @SalesNo        NVARCHAR(20),
            @SMExpKind      INT,
            @DeptSeq        INT,
            @EmpSeq         INT,
            @CustSeq        INT,
            @CustNo         NVARCHAR(30),   -- 추가 :: 20210226 장유경
            @ItemName       NVARCHAR(200),
            @ItemNo         NVARCHAR(100),
            @BillNo         NVARCHAR(20),
            @UMPriceTerms   INT,
            @RefNo          NVARCHAR(30),
            @UMChannel      INT

        --조회조건
    SELECT  @BizUnit        = ISNULL(BizUnit, 0),
            @SalesDateFr    = ISNULL(SalesDateFr, ''),
            @SalesDateTo    = ISNULL(SalesDateTo, ''),
            @SalesNo        = LTRIM(RTRIM(ISNULL(SalesNo, ''))),
            @SMExpKind      = ISNULL(SMExpKind, 0),
            @DeptSeq        = ISNULL(DeptSeq, 0),
            @EmpSeq         = ISNULL(EmpSeq, 0),
            @ItemName       = ISNULL(ItemName, ''),
            @ItemNo         = LTRIM(RTRIM(ISNULL(ItemNo, ''))),
            @CustSeq        = ISNULL(CustSeq, 0),
            @CustNo         = ISNULL(CustNo, ''),
            @BillNo         = ISNULL(BillNo, ''),
            @UMPriceTerms   = ISNULL(UMPriceTerms,0),
            @RefNo          = ISNULL(InvoiceRefNo, 0),
            @SourceTableSeq = ISNULL(SourceTableSeq, 0), -- 20150518 이범확 추가
            @SourceNo       = ISNULL(SourceNo, ''),      -- 20150518 이범확 추가
            @SourceRefNo    = ISNULL(SourceRefNo, ''),   -- 20150518 이범확 추가
            @UMChannel      = ISNULL(UMChannel  ,  0),   -- 20211215 김희연 추가
            @AssetSeq       = ISNULL(AssetSeq, 0)        -- 20230622 정민찬 추가
    FROM #BIZ_IN_DataBlock1
```

# 1. 관리번호 패턴 (진행조회 / 원천조회)

전표성 데이터(매출→Invoice→Order→BL 같은 연결고리)에서 "관리번호"를 뽑아낼 때는 매번 새로 조인 구조를 짜지 않고, 이 ERP의 **공용 추적 엔진**을 재사용한다.

| 구분 | 프로시저/테이블 | 역할 |
|---|---|---|
| 원천조회 엔진 | `_SWCOMSourceTracking` | 현재 전표의 "원천"(이전 단계) 전표 Seq/Serl을 추적 |
| 진행조회 엔진 | `_SWCOMProgressTracking` | 현재 전표를 "원천"으로 삼아 그 다음 단계(진행)로 생성된 전표를 추적 |
| 설정 테이블 | `_TCOMProgTable` | 각 전표(테이블)의 Seq/No/RefNo 컬럼명을 메타로 정의. `ProgMasterTableName`, `ProgTableSeqColumn`, `ProgTableRefNoColumn`, `ProgTableNoColumn` 등 |

**사용 패턴** (베이스 프로시저에 이미 있는 관례를 그대로 따름):

```sql
-- 1) 추적 대상 테이블명을 임시테이블에 등록
TRUNCATE TABLE #TMP_SOURCETABLE
TRUNCATE TABLE #TCOMSourceTracking

INSERT INTO #TMP_SOURCETABLE(TABLENAME)
SELECT '_TSLOrderItem'   -- 추적하고 싶은 대상 테이블

-- 2) 엔진 호출 (원천: 원천조회 / 진행: 진행조회)
EXEC _SWCOMSourceTracking @CompanySeq, '_TSLSalesItem', '#TSLSalesItemInv', 'SalesSeq', 'SalesSerl', ''

-- 3) 결과는 #TCOMSourceTracking(또는 #TCOMProgressTracking)의 Seq/Serl로 돌아옴 → 원하는 마스터 테이블에 조인해서 관리번호(No) 컬럼을 가져온다
```

> ⚠️ `_SWCOMSourceTracking`/`_SWCOMProgressTracking` 내부 구현은 길고 복잡해서 전체를 다 읽기보다, **베이스 프로시저가 이미 호출하고 있는 패턴을 그대로 복사**하는 게 안전하다. 새로운 추적 방향이 필요하면(예: A→B가 아니라 A→C) `_TCOMProgTable`에 해당 테이블 매핑이 있는지 먼저 확인할 것.

# 2. 다이나믹 컬럼 패턴 (거래처/품목 추가정보 · 기타분류)

화면에 "사용자가 설정한 커스텀 필드"를 동적으로 펼쳐 보여줄 때 쓰는 구조. 클라이언트가 **메타(캡션) 결과집합 + 값 결과집합**, 두 개를 받아서 그리드 컬럼을 동적으로 생성하는 방식이다.

### 2-1. 추가정보 (사용자정의 필드)

| 구분 | 테이블 | 핵심 컬럼 |
|---|---|---|
| 메타(캡션) | `_TCOMUserDefine` | `TableName`('_TDACust' 등), `DefineUnitSeq` |
| 값(거래처) | `_TDACustUserDefine` | `CustSeq`, `MngSerl`(=TitleSerl), `MngValText` |
| 값(품목) | `_TDAItemUserDefine` | `ItemSeq`, `MngSerl`(=TitleSerl), `MngValText` |

### 2-2. 기타분류 (다중 분류체계)

| 구분 | 테이블 | 핵심 컬럼 |
|---|---|---|
| 분류 정의 | `_TDADefineCustClass` / `_TDADefineItemClass` | `UMajorCustClass`/`UMajorItemClass`, `Description`, (품목은 `IsMaterial`로 자재 여부 구분) |
| 값(거래처) | `_TDACustClass` | `CustSeq`, `UMajorCustClass`, `UMCustClass` |
| 값(품목) | `_TDAItemClass` | `ItemSeq`, `UMajorItemClass`, `UMItemClass` |

> 🚨 **반드시 지킬 것 — 범위 한정(scoping) 규칙**
> 위 "값" 조회는 절대 `_TSLSales`/`_TSLSalesItem` 같은 원본 전체 테이블을 바로 조인하지 않는다. 그렇게 하면 조회조건과 무관하게 **회사 전체 거래처/품목**이 나와버린다 (실제로 1차 작성본에서 이 실수가 있었다).
> **올바른 방법**: 메인 그리드 쿼리를 `SELECT ... INTO #FinalGrid`로 먼저 임시테이블에 적재한 뒤, 모든 다이나믹 값 조회는 `(SELECT DISTINCT CustSeq FROM #FinalGrid)` / `(SELECT DISTINCT ItemSeq FROM #FinalGrid)` 로 범위를 한정해서 조인한다.

### 2-3. 자재(Material) 관련 주의사항

이 ERP에는 거래처/품목과 달리 **별도의 "자재 마스터" 테이블이 없다.** 품목마스터(`_TDAItem`)에서 `_TDADefineItemClass.IsMaterial='1'`로 분류된 것을 "자재"로 간주하는 방식과, 실제 BOM 투입자재(`_TPDROUItemProcMatAdd.MatItemSeq`)를 의미하는 두 가지 해석이 가능하므로, **화면 요구사항에 어느 쪽인지 반드시 확인 후 조인 기준을 정할 것.**

# 3. 참고 구현 (전체 예시)

위 패턴 2가지(관리번호 + 다이나믹컬럼)를 모두 적용한 실제 예시 프로시저:

- 베이스: `_SWSLExpBillSalesItemQuery` (수출매출품목조회)
- 신규: `_SWSLExpBillSalesItemMngDynQuery`
- 파일 위치(로컬): `F:\김가슬\ERPDEV\_SWSLExpBillSalesItemMngDynQuery_TEST.sql`

> 이 스냅샷에는 Notion에 첨부된 실제 .sql 예시 파일들(다이나믹 거래처/품목/자재, 원천조회/진행조회 등)은 포함되어 있지 않습니다.
> 실제 코드 패턴은 같은 폴더의 `dynamic-sheet-pattern.md`를 우선 참고하고, 더 많은 예시가 필요하면 Notion 페이지에서 직접 받아야 합니다.

# 4. SQL 작성가이드

SQL 작성가이드는 Notion 페이지에 첨부된 `D-001_SQL작성가이드.pptx`를 따른다 (이 스냅샷에는 미포함).

# 5. Naming 규칙

프로시저명/테이블명/프로그램명 등은 Notion 페이지에 첨부된 `공통_Naming규칙.xlsx`를 따른다 (이 스냅샷에는 미포함).

> 📌 DB가 readonly 환경에서 작성되어 **실행/검증이 안 된 초안**입니다. 배포 전 개발계에서 반드시 테스트하세요. 대표거래처/청구처 컬럼 소스, 자재 해석 등 TODO가 파일 상단 주석에 남아있습니다.
