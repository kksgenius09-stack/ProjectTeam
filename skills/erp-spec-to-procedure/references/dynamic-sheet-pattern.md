# 다이나믹시트 SQL 표준

사용자가 설정한 커스텀 필드(추가정보)나 다중 분류체계(기타분류)를 화면에 동적으로 컬럼으로 펼쳐 보여줄 때 쓰는 구조. 클라이언트가 **컬럼정의 + 그리드 + 값매트릭스, 정확히 3개의 결과집합**을 받아서 그리드 컬럼을 동적으로 생성한다. ("메타 결과집합 + 값 결과집합" 식으로 그룹마다 따로 만드는 게 아니다 — 이건 틀린 구조다.)

## 왜 매트릭스 형태인가

클라이언트는 "이 행의 이 컬럼엔 값이 없다"는 것도 알아야 그리드를 빈 칸으로 올바르게 그릴 수 있다. 값이 있는 것만 돌려주면 클라이언트가 어떤 (행,컬럼) 조합이 원래 없어야 하는 건지 판단할 수 없다. 그래서 그리드 × 컬럼정의를 `CROSS JOIN`해서 모든 조합을 만들고, 실제 값은 `LEFT OUTER JOIN` + `ISNULL`로 채운다 — 이렇게 하면 항상 완전한 사각형 매트릭스가 나온다.

## 결과집합 ① 컬럼정의

```sql
CREATE TABLE #Temp_DynCol
( ColIDX      INT IDENTITY(0,1)   -- 0부터 시작, 연속 번호 (클라이언트가 컬럼 순서로 씀)
, Title       NVARCHAR(100)       -- 그룹명 (예: '거래처정보', '품목정보', '자재정보')
, TitleSeq    INT                 -- 그룹 구분자 (0,1,2... 매트릭스에서 어느 UNION ALL 파트인지 구분용)
, Title2      NVARCHAR(100)       -- 실제 컬럼 캡션 (사용자가 설정한 필드명/분류명)
, TitleSeq2   INT                 -- 실제 키 (UserDefine의 TitleSerl, 또는 분류체계의 UMajorXxxClass)
, InputType   NVARCHAR(50)        -- enText/enFloat/enCodeHelp/enMask/enCombo/enCheck/enDate
, DecLen      INT                 -- 소수점 자리수 (float류만 의미 있음, 나머지는 NULL)
)
```

`InputType`은 `_TCOMUserDefine.SMInputType`을 **7종 전체** 매핑해야 한다. 3종만 매핑하고 나머지를 `enText`로 뭉개면 코드헬프/마스크/콤보 필드가 조용히 텍스트박스로 잘못 표시된다 — 겉보기엔 동작하는 것처럼 보여서 알아채기 어려운 버그다.

```sql
CASE A.SMInputType WHEN 1027001 THEN 'enText'
                   WHEN 1027002 THEN 'enFloat'
                   WHEN 1027003 THEN 'enCodeHelp'
                   WHEN 1027004 THEN 'enMask'
                   WHEN 1027005 THEN 'enCombo'
                   WHEN 1027006 THEN 'enCheck'
                   WHEN 1027007 THEN 'enDate'
                   ELSE 'enText' END
```

그룹이 여러 개면(예: 거래처/품목/자재 × 추가정보/기타분류 = 6그룹) 전부 이 **하나의** 테이블에 `UNION ALL`로 쌓는다. `TitleSeq`만 그룹마다 다르게 준다.

## 결과집합 ② 그리드

화면의 메인 조회 결과 그 자체다. 다만 **RowIDX를 0부터 매겨서 임시테이블에 적재**해야 한다 (매트릭스에서 행을 식별하는 키가 필요하기 때문):

```sql
SELECT  ROW_NUMBER() OVER (ORDER BY <베이스의 기존 ORDER BY 그대로>) - 1  AS RowIDX
      , <기존 베이스 SELECT 컬럼 전부 그대로>
  INTO  #RESULT_Xxx   -- 기존에 그냥 SELECT로 끝나던 걸 INTO로 바꾸고 RowIDX만 추가
  FROM  <기존 베이스 FROM/JOIN/WHERE 전부 그대로>
```

마지막 결과집합으로 `SELECT * FROM #RESULT_Xxx ORDER BY RowIDX`를 반환한다. 기존 베이스의 `ORDER BY`는 `ROW_NUMBER() OVER (ORDER BY ...)` 안으로 그대로 옮기면 된다 — `SELECT ... INTO`에서는 바깥쪽 `ORDER BY`가 어차피 의미 없다.

## 결과집합 ③ 값매트릭스

그룹별로 그리드 × 해당 그룹 컬럼정의를 `CROSS JOIN`하고, 실제 값 테이블을 `LEFT OUTER JOIN`한 뒤 전부 `UNION ALL`로 합친다:

```sql
SELECT  G.RowIDX, H.ColIDX, ISNULL(D.MngValText, '') AS AddInfoName
  FROM  #RESULT_Xxx AS G
        CROSS JOIN (SELECT * FROM #Temp_DynCol WHERE TitleSeq = 0) AS H
        LEFT OUTER JOIN _TDAItemUserDefine AS D WITH(NOLOCK)
                     ON D.CompanySeq = @CompanySeq
                    AND D.ItemSeq    = G.ItemSeq      -- 그리드에 있는 키 컬럼과 조인
                    AND D.MngSerl    = H.TitleSeq2
 UNION ALL
SELECT  G.RowIDX, H.ColIDX, ISNULL(M.MinorName, '') AS AddInfoName
  FROM  #RESULT_Xxx AS G
        CROSS JOIN (SELECT * FROM #Temp_DynCol WHERE TitleSeq = 1) AS H
        LEFT OUTER JOIN _TDAItemClass AS IC WITH(NOLOCK)
                     ON IC.CompanySeq      = @CompanySeq
                    AND IC.ItemSeq         = G.ItemSeq
                    AND IC.UMajorItemClass = H.TitleSeq2
        LEFT OUTER JOIN _TDAUMinor    AS M  WITH(NOLOCK)   -- 분류 코드의 표시 캡션
                     ON M.CompanySeq       = @CompanySeq
                    AND M.MajorSeq         = IC.UMajorItemClass
                    AND M.MinorSeq         = IC.UMItemClass
 ORDER BY RowIDX, ColIDX
```

**범위 한정(scoping) 규칙 — 반드시 지킬 것**: 값 조회는 절대 `_TDAItem`/`_TDACust` 같은 원본 전체 테이블을 조건 없이 조인하지 않는다. 매트릭스는 `#RESULT_Xxx`(이미 조회조건으로 필터링된 그리드)를 `CROSS JOIN`의 왼쪽에 두므로 자연히 범위가 한정되지만, 혹시 그리드 밖에서 별도로 값을 조회해야 하는 경우라면 반드시 `(SELECT DISTINCT ItemSeq FROM #RESULT_Xxx)`처럼 그리드로 범위를 좁혀서 조인한다. 이걸 빼먹으면 조회조건과 무관하게 **회사 전체 데이터**가 나와버린다 — 실제로 1차 작성본에서 이 실수가 있었다.

## 그룹별 소스 테이블 매핑

### 추가정보 (사용자정의 필드)
| 구분 | 테이블 | 핵심 컬럼 |
|---|---|---|
| 메타(컬럼정의) | `_TCOMUserDefine` | `TableName`, `DefineUnitSeq`, `Title`, `TitleSerl`, `SMInputType`, `DecLen` |
| 값(거래처) | `_TDACustUserDefine` | `CustSeq`, `MngSerl`(=TitleSerl), `MngValText` |
| 값(품목/자재) | `_TDAItemUserDefine` | `ItemSeq`, `MngSerl`(=TitleSerl), `MngValText` |

`DefineUnitSeq`는 같은 테이블(`_TDAItem`)이라도 "제품용 추가정보 세트"와 "자재용 추가정보 세트"가 다른 값으로 나뉘어 있을 수 있다(실제로 품목=8010001, 자재=8010002, 거래처=2004 로 확인된 적이 있다 — 하지만 이건 **이 회사 한정 사례이지 고정값이 아니다**). 매직넘버는 절대 그대로 베껴쓰지 말고 매번:

```sql
SELECT DISTINCT DefineUnitSeq FROM _TCOMUserDefine WHERE TableName = '대상테이블명'
```
로 직접 확인한다. 값이 여러 개 나오면 무엇이 "품목/자재/제품" 중 어디에 해당하는지, 코드마스터(`_TDASMinor` 등에 같은 숫자가 캡션으로 등록돼 있는 경우가 많다)로 교차 확인한다.

### 기타분류 (다중 분류체계)
| 구분 | 테이블 | 핵심 컬럼 |
|---|---|---|
| 분류 정의 | `_TDADefineCustClass` / `_TDADefineItemClass` | `UMajorCustClass`/`UMajorItemClass`, `Description`, (품목만 `IsMaterial`) |
| 값(거래처) | `_TDACustClass` | `CustSeq`, `UMajorCustClass`, `UMCustClass` |
| 값(품목/자재) | `_TDAItemClass` | `ItemSeq`, `UMajorItemClass`, `UMItemClass` |
| 값 캡션 | `_TDAUMinor` | `MajorSeq`(=UMajorXxxClass), `MinorSeq`(=UMXxxClass), `MinorName` |

**자재 관련 주의**: 이 ERP에는 거래처/품목과 달리 별도의 "자재 마스터" 테이블이 없다. 품목마스터(`_TDAItem`)에서 `_TDADefineItemClass.IsMaterial='1'`로 분류된 걸 "자재"로 간주하는 방식과, 실제 BOM 투입자재(`_TPDROUItemProcMatAdd.MatItemSeq`)를 의미하는 두 가지 해석이 가능하다. 화면 요구사항에 어느 쪽인지 실데이터로 확인하고(`SELECT UMajorItemClass, Description, IsMaterial FROM _TDADefineItemClass WHERE CompanySeq=1` 로 분류 그룹별 `IsMaterial` 값을 직접 보고) 조인 기준을 정한다.

## 참고용 전체 예시 (DB 실행 검증 완료 — 단순 1그룹 버전)

Notion 컨벤션 페이지 Section 3에 첨부된 `예시_fst_Test_ItemAddInfoDynamicQuery.sql`이 품목 추가정보 1종만 쓰는 가장 단순한 형태의 검증된 예시다. 새 작업을 시작할 때 이 파일을 먼저 열어서 구조를 그대로 베끼고, 그룹을 추가할 때마다 컬럼정의/값매트릭스에 `UNION ALL` 파트를 하나씩 늘리는 식으로 확장하는 게 제일 안전하다.
