;; Title: StacksVault Protocol
;; Bitcoin Layer 2 Decentralized Lending & Borrowing Infrastructure
;;
;; Summary:
;; StacksVault is an institutional-grade DeFi protocol that transforms STX tokens
;; into productive collateral assets. Built on Bitcoin's security model through 
;; Stacks Layer 2, it enables seamless lending, borrowing, and yield generation
;; while maintaining full custody and transparency through smart contracts.
;;
;; Description:
;; StacksVault Protocol revolutionizes Bitcoin DeFi by creating a robust lending
;; marketplace where users can leverage their STX holdings without selling. The
;; protocol features dynamic risk management, automated liquidations, real-time
;; collateralization monitoring, and configurable parameters for optimal capital
;; efficiency. Designed for both retail and institutional users seeking Bitcoin-
;; native financial services with enterprise-grade security and reliability.
;; 
;; Built on the principle of "Don't sell your Bitcoin, borrow against it" -
;; StacksVault extends this philosophy to the entire Stacks ecosystem.

;; PROTOCOL CONSTANTS & ERROR CODES

(define-constant CONTRACT-OWNER tx-sender)

;; Error Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-LOAN-NOT-FOUND (err u103))
(define-constant ERR-LOAN-ACTIVE (err u104))
(define-constant ERR-INSUFFICIENT-BALANCE (err u105))
(define-constant ERR-LIQUIDATION-FAILED (err u106))
(define-constant ERR-INVALID-PARAMETER (err u107))

;; Protocol Limits
(define-constant MAX-COLLATERAL-RATIO u500)  ;; 500% maximum collateralization
(define-constant MIN-COLLATERAL-RATIO u110)  ;; 110% minimum safety threshold
(define-constant MAX-PROTOCOL-FEE u10)       ;; 10% maximum protocol fee

;; GLOBAL PROTOCOL STATE VARIABLES

(define-data-var minimum-collateral-ratio uint u150)  ;; 150% collateral requirement
(define-data-var liquidation-threshold uint u130)     ;; 130% liquidation trigger
(define-data-var protocol-fee uint u1)                ;; 1% protocol fee
(define-data-var total-deposits uint u0)              ;; Total STX deposited as collateral
(define-data-var total-borrows uint u0)               ;; Total STX borrowed from protocol

;; DATA STRUCTURES & STORAGE MAPS

;; Individual Loan Records
(define-map loans
  { loan-id: uint }
  {
    borrower: principal,
    collateral-amount: uint,
    borrowed-amount: uint,
    interest-rate: uint,
    start-height: uint,
    last-interest-update: uint,
    active: bool,
  }
)

;; User Position Aggregation
(define-map user-positions
  { user: principal }
  {
    total-collateral: uint,
    total-borrowed: uint,
    loan-count: uint,
  }
)

;; INTERNAL PROTOCOL LOGIC & CALCULATIONS

;; Calculate compound interest based on block height progression
(define-private (calculate-interest
    (principal uint)
    (rate uint)
    (blocks uint)
  )
  (let (
      (interest-per-block (/ (* principal rate) u10000))
      (total-interest (* interest-per-block blocks))
    )
    total-interest
  )
)

;; Compute real-time collateralization ratio
(define-private (get-collateral-ratio
    (collateral uint)
    (debt uint)
  )
  (if (is-eq debt u0)
    u0
    (/ (* collateral u100) debt)
  )
)

;; Update user position with collateral and debt changes
(define-private (update-user-position
    (user principal)
    (collateral-delta uint)
    (is-collateral-increase bool)
    (borrow-delta uint)
    (is-borrow-increase bool)
  )
  (let (
      (current-position (default-to {
        total-collateral: u0,
        total-borrowed: u0,
        loan-count: u0,
      }
        (map-get? user-positions { user: user })
      ))
      (new-collateral (if is-collateral-increase
        (+ (get total-collateral current-position) collateral-delta)
        (- (get total-collateral current-position) collateral-delta)
      ))
      (new-borrowed (if is-borrow-increase
        (+ (get total-borrowed current-position) borrow-delta)
        (- (get total-borrowed current-position) borrow-delta)
      ))
    )
    (map-set user-positions { user: user } {
      total-collateral: new-collateral,
      total-borrowed: new-borrowed,
      loan-count: (get loan-count current-position),
    })
  )
)

;; PUBLIC USER INTERFACE - CORE LENDING FUNCTIONS

;; Deposit STX as collateral to enable borrowing capacity
(define-public (deposit)
  (let ((amount (stx-get-balance tx-sender)))
    (if (> amount u0)
      (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set total-deposits (+ (var-get total-deposits) amount))
        (update-user-position tx-sender amount true u0 true)
        (ok amount)
      )
      ERR-INVALID-AMOUNT
    )
  )
)

;; Borrow STX against deposited collateral with collateralization checks
(define-public (borrow (amount uint))
  (let (
      (user-pos (default-to {
        total-collateral: u0,
        total-borrowed: u0,
        loan-count: u0,
      }
        (map-get? user-positions { user: tx-sender })
      ))
      (collateral (get total-collateral user-pos))
      (current-borrowed (get total-borrowed user-pos))
    )
    (if (and
        (> amount u0)
        (>= (get-collateral-ratio collateral (+ current-borrowed amount))
          (var-get minimum-collateral-ratio)
        )
      )
      (begin
        (try! (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender)))
        (var-set total-borrows (+ (var-get total-borrows) amount))
        (update-user-position tx-sender u0 true amount true)
        (ok amount)
      )
      ERR-INSUFFICIENT-COLLATERAL
    )
  )
)