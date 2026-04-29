# RISC-V CPU-Based SoC Design (RV32I)

## Overview
RV32I 기반 RISC-V CPU를 설계하고,  
UART, SPI 등 주변장치를 memory-mapped I/O로 통합한  
**단일 사이클 SoC 시스템**을 구현하였다.

GCC로 컴파일한 C 코드를 firmware로 로드하여  
hardware-software 통합 검증까지 수행하였다.

---

## Key Contributions
- RV32I ISA 기반 CPU core 직접 설계 (fetch–decode–execute–memory–writeback)
- Memory-mapped I/O 기반 peripheral 제어 구조 구현
- UART, SPI, GPIO 등 SoC-level integration
- GCC toolchain을 이용한 firmware 실행 및 검증

---

## Design Details

### 1. CPU Core (rv32i_cpu.v)
- 단일 사이클 구조
- 5-stage 동작 흐름:
  - Fetch → Decode → Execute → Memory → Write-back

#### 지원 명령어
- 총 40개 RV32I instruction

---

### 2. ALU (alu.v)
- 10개 연산 지원

| 종류 | 연산 |
|------|------|
| 산술 | ADD, SUB |
| 논리 | AND, OR, XOR |
| 시프트 | SLL, SRL, SRA |
| 비교 | SLT, SLTU |

- 상태 플래그: N, Z, C, V

---

### 3. Memory System
- Dual-port memory
  - Instruction fetch / data access 동시 처리
- RAM (8KB): 코드 + 데이터 저장

---

### 4. Memory-Mapped I/O

| Address Range | Device | Description |
|--------------|--------|------------|
| 0x0000 ~ 0x1FFF | RAM | Instruction/Data |
| 0xFFFF1000 | Keypad | 입력 인터페이스 |
| 0xFFFF2000 | GPIO | LED / 7-seg |
| 0xFFFF3000 | UART | Serial (115200 bps) |
| 0xFFFF4000 | SPI | SPI Master |

CPU는 일반 load/store로 peripheral 제어

---

### 5. Communication Modules

#### UART
- FIFO 기반 TX/RX buffering
- 비동기 시리얼 통신 지원

#### SPI
- Master mode (Mode 0)
- register 기반 제어

---

## Control Flow

1. GCC로 C 코드 컴파일
2. 바이너리를 memory에 로드
3. CPU가 instruction fetch 수행
4. peripheral 접근 시 memory-mapped address 사용
5. 결과를 memory 및 IO에 반영

---

## Performance
- Clock: 10 MHz
- Single-cycle execution
- Memory access: 1 cycle
- Peripheral access: 1~5 cycles

---

## Verification

- RISC-V GCC로 컴파일된 프로그램 실행
- waveform 기반 PC 및 register 추적
- memory 결과 검증

RTL simulation + firmware execution까지 확인

---

## Key Insights
- Memory-mapped I/O는 HW/SW 인터페이스를 단순화함
- CPU 성능보다 **data movement 및 IO 구조가 시스템 성능에 영향**
- SoC 설계에서는 peripheral integration이 핵심

---

## Tech Stack
- Verilog
- RISC-V (RV32I)
- GCC Toolchain
- UART / SPI
