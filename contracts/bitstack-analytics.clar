;; Title: BitStack Analytics Protocol
;; Summary: A comprehensive DeFi staking and governance platform built 
;;          for the Stacks ecosystem with Bitcoin-backed security
;; Description: This protocol enables users to stake STX tokens with 
;;              tiered rewards, participate in decentralized governance,
;;              and earn ANALYTICS tokens through a sophisticated 
;;              multi-tier system designed for long-term value creation
;;              and community-driven decision making on Bitcoin L2

;; TOKEN DEFINITIONS
(define-fungible-token ANALYTICS-TOKEN u0)

;; CONSTANTS & ERRORS
(define-constant CONTRACT-OWNER tx-sender)

;; Error Constants
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-PROTOCOL (err u1001))
(define-constant ERR-INVALID-AMOUNT (err u1002))
(define-constant ERR-INSUFFICIENT-STX (err u1003))
(define-constant ERR-COOLDOWN-ACTIVE (err u1004))
(define-constant ERR-NO-STAKE (err u1005))
(define-constant ERR-BELOW-MINIMUM (err u1006))
(define-constant ERR-PAUSED (err u1007))

;; STATE VARIABLES
(define-data-var contract-paused bool false)
(define-data-var emergency-mode bool false)
(define-data-var stx-pool uint u0)
(define-data-var base-reward-rate uint u500) ;; 5% base rate (100 = 1%)
(define-data-var bonus-rate uint u100) ;; 1% bonus for longer staking
(define-data-var minimum-stake uint u1000000) ;; Minimum stake amount (1 STX)
(define-data-var cooldown-period uint u1440) ;; 24 hour cooldown in blocks
(define-data-var proposal-count uint u0)

;; DATA STRUCTURES

;; Governance Proposals Mapping
(define-map Proposals
  { proposal-id: uint }
  {
    creator: principal,
    description: (string-utf8 256),
    start-block: uint,
    end-block: uint,
    executed: bool,
    votes-for: uint,
    votes-against: uint,
    minimum-votes: uint,
  }
)

;; User Position Tracking
(define-map UserPositions
  principal
  {
    total-collateral: uint,
    total-debt: uint,
    health-factor: uint,
    last-updated: uint,
    stx-staked: uint,
    analytics-tokens: uint,
    voting-power: uint,
    tier-level: uint,
    rewards-multiplier: uint,
  }
)

;; Staking Position Management
(define-map StakingPositions
  principal
  {
    amount: uint,
    start-block: uint,
    last-claim: uint,
    lock-period: uint,
    cooldown-start: (optional uint),
    accumulated-rewards: uint,
  }
)

;; Tier Level Configuration
(define-map TierLevels
  uint
  {
    minimum-stake: uint,
    reward-multiplier: uint,
    features-enabled: (list 10 bool),
  }
)

;; PRIVATE FUNCTIONS

;; Determines user tier based on stake amount
(define-private (get-tier-info (stake-amount uint))
  (if (>= stake-amount u10000000) ;; Diamond Tier: 10+ STX
    {
      tier-level: u3,
      reward-multiplier: u200,
    }
    (if (>= stake-amount u5000000) ;; Gold Tier: 5+ STX
      {
        tier-level: u2,
        reward-multiplier: u150,
      }
      {
        tier-level: u1,
        reward-multiplier: u100,
      } ;; Silver Tier: 1+ STX
    )
  )
)

;; Calculates lock period multiplier for enhanced rewards
(define-private (calculate-lock-multiplier (lock-period uint))
  (if (>= lock-period u8640) ;; 2 months lock
    u150 ;; 1.5x multiplier
    (if (>= lock-period u4320) ;; 1 month lock
      u125 ;; 1.25x multiplier
      u100 ;; No lock multiplier
    )
  )
)

;; Computes staking rewards based on time and tier
(define-private (calculate-rewards
    (user principal)
    (blocks uint)
  )
  (let (
      (staking-position (unwrap! (map-get? StakingPositions user) u0))
      (user-position (unwrap! (map-get? UserPositions user) u0))
      (stake-amount (get amount staking-position))
      (base-rate (var-get base-reward-rate))
      (multiplier (get rewards-multiplier user-position))
    )
    ;; Formula: (stake * rate * multiplier * blocks) / (100 * 144 blocks/day)
    (/ (* (* (* stake-amount base-rate) multiplier) blocks) u14400000)
  )
)

;; Validates proposal description meets requirements
(define-private (is-valid-description (desc (string-utf8 256)))
  (and
    (>= (len desc) u10) ;; Minimum 10 characters
    (<= (len desc) u256) ;; Maximum 256 characters
  )
)

;; Validates lock period options
(define-private (is-valid-lock-period (lock-period uint))
  (or
    (is-eq lock-period u0) ;; No lock
    (is-eq lock-period u4320) ;; 1 month (30 days * 144 blocks)
    (is-eq lock-period u8640) ;; 2 months (60 days * 144 blocks)
  )
)

;; Validates voting period parameters
(define-private (is-valid-voting-period (period uint))
  (and
    (>= period u100) ;; Minimum ~17 hours
    (<= period u2880) ;; Maximum ~20 days
  )
)

;; PUBLIC FUNCTIONS

;; Initialize contract with tier structure
(define-public (initialize-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    ;; Configure Silver Tier (Entry Level)
    (map-set TierLevels u1 {
      minimum-stake: u1000000, ;; 1 STX minimum
      reward-multiplier: u100, ;; 1x base rewards
      features-enabled: (list true false false false false false false false false false),
    })
    ;; Configure Gold Tier (Premium)
    (map-set TierLevels u2 {
      minimum-stake: u5000000, ;; 5 STX minimum
      reward-multiplier: u150, ;; 1.5x rewards boost
      features-enabled: (list true true true false false false false false false false),
    })
    ;; Configure Diamond Tier (Elite)
    (map-set TierLevels u3 {
      minimum-stake: u10000000, ;; 10 STX minimum
      reward-multiplier: u200, ;; 2x rewards boost
      features-enabled: (list true true true true true false false false false false),
    })
    (ok true)
  )
)