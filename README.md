# RTL Tiled Matrix Multiplication Neural Network Accelerator

Verilog로 구현한 타일 기반 행렬곱 신경망 가속기

---

## 개요

본 프로젝트는 Fully Connected 기반 신경망 연산을 RTL 수준에서 구현한 가속기이다.
행렬 곱 연산을 **타일링 + Systolic Array 구조**로 수행하며, 전체 연산 흐름은 다음과 같다.
<img width="1539" height="298" alt="image" src="https://github.com/user-attachments/assets/29f308bb-dbea-478e-a7ec-9d9dd204c1fb" />


---

## 구조

### 🔹 전체 데이터 흐름

* FC1: W1 × X → X1
* Normalization: X1 → X2 (bit shift 기반)
* ReLU: X2 → X3 (음수 제거)
* FC2: W2 × X3 → Y

---

### 🔹 핵심 모듈

#### 1. Systolic Array (4×4)

* 총 16개의 Systolic Element(SE)
* 각 SE는 MAC 연산 수행 (1 mul + 1 add / cycle)
* 총 32 ops/cycle 처리 가능

---

#### 2. Tiled Matrix Multiplication

* 8×8 행렬 → 4개 tile
* 8×16 행렬 → 8개 tile
* 타일 단위로 순차 처리

연산 단계:

```id="pipe01"
LOAD → COMPUTE → LOAD → COMPUTE → WRITE
```

---

#### 3. Normalization 모듈

* 16-bit 입력 → 8-bit 출력
* 방식:

  * 5-bit right shift (÷32)
  * [12:5] 비트 추출

--> 연산 overflow 및 다음 stage 연산량 감소 목적

---

#### 4. ReLU 모듈

* MSB 기반 판단

  * MSB = 1 → 0 출력
  * MSB = 0 → 그대로 출력

---

#### 5. 메모리 인터페이스

* 단일 포트 구조
* 제어 신호:

  * `en`, `re`, `we`
* 한 사이클에 read 또는 write 중 하나만 수행

---

## 동작 특징

* 타일 단위로 연산이 순차적으로 진행됨
* 각 타일 완료 시 결과를 메모리에 저장
* Batch 모드에 따라 타일 개수 및 주소 계산 방식 변화

Batch 모드:

* Batch 8 → 4 tiles
* Batch 16 → 8 tiles

---

## 성능

* Peak Bandwidth: 200 MB/s
* Peak Performance: 3.2 GOPS
* Latency:

  * Batch 8: 15.6 µs
  * Batch 16: 31.2 µs
* Utilization: 약 40%

---

## 참고

자세한 파형 분석 및 설계 설명은 보고서를 참고:

* Final Project Report.pdf
