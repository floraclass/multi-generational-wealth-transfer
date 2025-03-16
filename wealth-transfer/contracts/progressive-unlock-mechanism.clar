;; progressive-unlock.clar
;; A smart contract for progressive asset unlocking based on age, achievements, and emergency needs

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-BENEFICIARY-EXISTS (err u101))
(define-constant ERR-BENEFICIARY-NOT-FOUND (err u102))
(define-constant ERR-INVALID-PARAMETER (err u103))
(define-constant ERR-IDENTITY-VERIFICATION-FAILED (err u104))
(define-constant ERR-UNLOCK-CONDITION-NOT-MET (err u105))
(define-constant ERR-ACHIEVEMENT-NOT-FOUND (err u106))
(define-constant ERR-EMERGENCY-REQUEST-EXISTS (err u107))
(define-constant ERR-EMERGENCY-REQUEST-NOT-FOUND (err u108))
(define-constant ERR-INSUFFICIENT-APPROVALS (err u109))
(define-constant ERR-ALREADY-UNLOCKED (err u110))
(define-constant ERR-MILESTONE-NOT-FOUND (err u111))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var identity-verifier principal tx-sender)
(define-data-var achievement-verifier principal tx-sender)
(define-data-var min-governance-approvals uint u3)

;; Data maps
(define-map beneficiaries
  { address: principal }
  {
    did: (string-ascii 100), ;; Decentralized identity
    birth-timestamp: uint,
    identity-verified: bool,
    total-allocation: uint,
    unlocked-amount: uint,
    emergency-fund-amount: uint
  }
)

(define-map age-milestones
  { beneficiary: principal, age: uint }
  {
    amount: uint,
    unlocked: bool,
    unlock-timestamp: uint
  }
)

(define-map achievements
  { achievement-id: uint }
  {
    title: (string-ascii 100),
    description: (string-utf8 256),
    reward-amount: uint,
    verification-required: bool
  }
)

(define-map beneficiary-achievements
  { beneficiary: principal, achievement-id: uint }
  {
    verified: bool,
    unlocked: bool,
    verification-timestamp: (optional uint)
  }
)

(define-map emergency-requests
  { request-id: uint }
  {
    beneficiary: principal,
    amount: uint,
    reason: (string-utf8 256),
    request-timestamp: uint,
    status: (string-ascii 20), ;; "pending", "approved", "rejected", "completed"
    approvals: uint,
    rejections: uint
  }
)

(define-map governance-votes
  { request-id: uint, voter: principal }
  {
    approved: bool,
    timestamp: uint
  }
)

(define-map governance-members
  { address: principal }
  { active: bool }
)

;; Variables
(define-data-var achievement-nonce uint u0)
(define-data-var emergency-request-nonce uint u0)

;; Read-only functions

(define-read-only (get-beneficiary (address principal))
  (map-get? beneficiaries { address: address })
)

(define-read-only (get-age-milestone (beneficiary principal) (age uint))
  (map-get? age-milestones { beneficiary: beneficiary, age: age })
)

(define-read-only (get-achievement (achievement-id uint))
  (map-get? achievements { achievement-id: achievement-id })
)

(define-read-only (get-beneficiary-achievement (beneficiary principal) (achievement-id uint))
  (map-get? beneficiary-achievements { beneficiary: beneficiary, achievement-id: achievement-id })
)

(define-read-only (get-emergency-request (request-id uint))
  (map-get? emergency-requests { request-id: request-id })
)

(define-read-only (get-governance-vote (request-id uint) (voter principal))
  (map-get? governance-votes { request-id: request-id, voter: voter })
)

(define-read-only (is-governance-member (address principal))
  (default-to false (get active (map-get? governance-members { address: address })))
)

(define-read-only (calculate-current-age (birth-timestamp uint))
  (let
    (
      (current-time stacks-block-height)
      (seconds-per-year u31536000) ;; 365 days * 24 hours * 60 minutes * 60 seconds
      (blocks-per-year (/ seconds-per-year u600)) ;; Assuming 10-minute block times
    )
    (/ (- current-time birth-timestamp) blocks-per-year)
  )
)

;; Public functions

;; Register a new beneficiary
(define-public (register-beneficiary 
    (beneficiary principal) 
    (did (string-ascii 100))
    (birth-timestamp uint)
    (total-allocation uint)
    (emergency-fund-percentage uint))
  (let
    (
      (emergency-amount (/ (* total-allocation emergency-fund-percentage) u100))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (get-beneficiary beneficiary)) ERR-BENEFICIARY-EXISTS)
    (asserts! (<= emergency-fund-percentage u30) ERR-INVALID-PARAMETER) ;; Max 30% for emergency fund
    
    (map-set beneficiaries
      { address: beneficiary }
      {
        did: did,
        birth-timestamp: birth-timestamp,
        identity-verified: false,
        total-allocation: total-allocation,
        unlocked-amount: u0,
        emergency-fund-amount: emergency-amount
      }
    )
    (ok true)
  )
)

;; Verify beneficiary identity
(define-public (verify-beneficiary-identity (beneficiary principal))
  (let
    (
      (beneficiary-data (unwrap! (get-beneficiary beneficiary) ERR-BENEFICIARY-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get identity-verifier)) ERR-NOT-AUTHORIZED)
    
    (map-set beneficiaries
      { address: beneficiary }
      (merge beneficiary-data { identity-verified: true })
    )
    (ok true)
  )
)

;; Add age milestone for a beneficiary
(define-public (add-age-milestone (beneficiary principal) (age uint) (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (get-beneficiary beneficiary)) ERR-BENEFICIARY-NOT-FOUND)
    (asserts! (is-none (get-age-milestone beneficiary age)) ERR-INVALID-PARAMETER)
    
    (map-set age-milestones
      { beneficiary: beneficiary, age: age }
      {
        amount: amount,
        unlocked: false,
        unlock-timestamp: u0
      }
    )
    (ok true)
  )
)

;; Unlock age-based milestone
(define-public (unlock-age-milestone (beneficiary principal) (age uint))
  (let
    (
      (beneficiary-data (unwrap! (get-beneficiary beneficiary) ERR-BENEFICIARY-NOT-FOUND))
      (milestone (unwrap! (get-age-milestone beneficiary age) ERR-MILESTONE-NOT-FOUND))
      (current-age (calculate-current-age (get birth-timestamp beneficiary-data)))
    )
    ;; Can be called by beneficiary or contract owner
    (asserts! (or (is-eq tx-sender beneficiary) (is-eq tx-sender (var-get contract-owner))) ERR-NOT-AUTHORIZED)
    (asserts! (get identity-verified beneficiary-data) ERR-IDENTITY-VERIFICATION-FAILED)
    (asserts! (>= current-age age) ERR-UNLOCK-CONDITION-NOT-MET)
    (asserts! (not (get unlocked milestone)) ERR-ALREADY-UNLOCKED)
    
    ;; Update milestone
    (map-set age-milestones
      { beneficiary: beneficiary, age: age }
      (merge milestone 
        { 
          unlocked: true,
          unlock-timestamp: stacks-block-height
        }
      )
    )
    
    ;; Update beneficiary's unlocked amount
    (map-set beneficiaries
      { address: beneficiary }
      (merge beneficiary-data 
        { 
          unlocked-amount: (+ (get unlocked-amount beneficiary-data) (get amount milestone))
        }
      )
    )
    
    (ok (get amount milestone))
  )
)

;; Create a new achievement
(define-public (create-achievement 
    (title (string-ascii 100))
    (description (string-utf8 256))
    (reward-amount uint)
    (verification-required bool))
  (let
    (
      (achievement-id (+ (var-get achievement-nonce) u1))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    
    (map-set achievements
      { achievement-id: achievement-id }
      {
        title: title,
        description: description,
        reward-amount: reward-amount,
        verification-required: verification-required
      }
    )
    (var-set achievement-nonce achievement-id)
    (ok achievement-id)
  )
)

;; Assign achievement to beneficiary
(define-public (assign-achievement (beneficiary principal) (achievement-id uint))
  (let
    (
      (achievement (unwrap! (get-achievement achievement-id) ERR-ACHIEVEMENT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (get-beneficiary beneficiary)) ERR-BENEFICIARY-NOT-FOUND)
    (asserts! (is-none (get-beneficiary-achievement beneficiary achievement-id)) ERR-INVALID-PARAMETER)
    
    (map-set beneficiary-achievements
      { beneficiary: beneficiary, achievement-id: achievement-id }
      {
        verified: (not (get verification-required achievement)),
        unlocked: false,
        verification-timestamp: (if (get verification-required achievement) none (some stacks-block-height))
      }
    )
    (ok true)
  )
)

;; Verify achievement completion
(define-public (verify-achievement (beneficiary principal) (achievement-id uint))
  (let
    (
      (achievement (unwrap! (get-achievement achievement-id) ERR-ACHIEVEMENT-NOT-FOUND))
      (beneficiary-achievement (unwrap! (get-beneficiary-achievement beneficiary achievement-id) ERR-ACHIEVEMENT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get achievement-verifier)) ERR-NOT-AUTHORIZED)
    (asserts! (get verification-required achievement) ERR-INVALID-PARAMETER)
    (asserts! (not (get verified beneficiary-achievement)) ERR-ALREADY-UNLOCKED)
    
    (map-set beneficiary-achievements
      { beneficiary: beneficiary, achievement-id: achievement-id }
      (merge beneficiary-achievement 
        { 
          verified: true,
          verification-timestamp: (some stacks-block-height)
        }
      )
    )
    (ok true)
  )
)

;; Unlock achievement reward
(define-public (unlock-achievement (beneficiary principal) (achievement-id uint))
  (let
    (
      (beneficiary-data (unwrap! (get-beneficiary beneficiary) ERR-BENEFICIARY-NOT-FOUND))
      (achievement (unwrap! (get-achievement achievement-id) ERR-ACHIEVEMENT-NOT-FOUND))
      (beneficiary-achievement (unwrap! (get-beneficiary-achievement beneficiary achievement-id) ERR-ACHIEVEMENT-NOT-FOUND))
    )
    ;; Can be called by beneficiary or contract owner
    (asserts! (or (is-eq tx-sender beneficiary) (is-eq tx-sender (var-get contract-owner))) ERR-NOT-AUTHORIZED)
    (asserts! (get identity-verified beneficiary-data) ERR-IDENTITY-VERIFICATION-FAILED)
    (asserts! (get verified beneficiary-achievement) ERR-UNLOCK-CONDITION-NOT-MET)
    (asserts! (not (get unlocked beneficiary-achievement)) ERR-ALREADY-UNLOCKED)
    
    ;; Update achievement status
    (map-set beneficiary-achievements
      { beneficiary: beneficiary, achievement-id: achievement-id }
      (merge beneficiary-achievement { unlocked: true })
    )
    
    ;; Update beneficiary's unlocked amount
    (map-set beneficiaries
      { address: beneficiary }
      (merge beneficiary-data 
        { 
          unlocked-amount: (+ (get unlocked-amount beneficiary-data) (get reward-amount achievement))
        }
      )
    )
    
    (ok (get reward-amount achievement))
  )
)

;; Create emergency fund request
(define-public (request-emergency-funds (amount uint) (reason (string-utf8 256)))
  (let
    (
      (beneficiary-data (unwrap! (get-beneficiary tx-sender) ERR-BENEFICIARY-NOT-FOUND))
      (request-id (+ (var-get emergency-request-nonce) u1))
    )
    (asserts! (get identity-verified beneficiary-data) ERR-IDENTITY-VERIFICATION-FAILED)
    (asserts! (<= amount (get emergency-fund-amount beneficiary-data)) ERR-INVALID-PARAMETER)
    
    (map-set emergency-requests
      { request-id: request-id }
      {
        beneficiary: tx-sender,
        amount: amount,
        reason: reason,
        request-timestamp: stacks-block-height,
        status: "pending",
        approvals: u0,
        rejections: u0
      }
    )
    (var-set emergency-request-nonce request-id)
    (ok request-id)
  )
)

;; Vote on emergency fund request
(define-public (vote-on-emergency-request (request-id uint) (approve bool))
  (let
    (
      (request (unwrap! (get-emergency-request request-id) ERR-EMERGENCY-REQUEST-NOT-FOUND))
    )
    (asserts! (is-governance-member tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "pending") ERR-INVALID-PARAMETER)
    (asserts! (is-none (get-governance-vote request-id tx-sender)) ERR-INVALID-PARAMETER)
    
    ;; Record the vote
    (map-set governance-votes
      { request-id: request-id, voter: tx-sender }
      {
        approved: approve,
        timestamp: stacks-block-height
      }
    )
    
    ;; Update request with new approval/rejection count
    (map-set emergency-requests
      { request-id: request-id }
      (merge request 
        { 
          approvals: (if approve (+ (get approvals request) u1) (get approvals request)),
          rejections: (if approve (get rejections request) (+ (get rejections request) u1))
        }
      )
    )
    
    (ok true)
  )
)

;; Finalize emergency fund request
(define-public (finalize-emergency-request (request-id uint))
  (let
    (
      (request (unwrap! (get-emergency-request request-id) ERR-EMERGENCY-REQUEST-NOT-FOUND))
      (beneficiary-data (unwrap! (get-beneficiary (get beneficiary request)) ERR-BENEFICIARY-NOT-FOUND))
      (min-approvals (var-get min-governance-approvals))
      (new-status (if (>= (get approvals request) min-approvals) "approved" "rejected"))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status request) "pending") ERR-INVALID-PARAMETER)
    (asserts! (or 
      (>= (get approvals request) min-approvals)
      (>= (get rejections request) min-approvals)
    ) ERR-INSUFFICIENT-APPROVALS)
    
    ;; Update request status
    (map-set emergency-requests
      { request-id: request-id }
      (merge request { status: new-status })
    )
    
    ;; If approved, update beneficiary's unlocked amount
    (if (is-eq new-status "approved")
      (map-set beneficiaries
        { address: (get beneficiary request) }
        (merge beneficiary-data 
          { 
            unlocked-amount: (+ (get unlocked-amount beneficiary-data) (get amount request)),
            emergency-fund-amount: (- (get emergency-fund-amount beneficiary-data) (get amount request))
          }
        )
      )
      true
    )
    
    (ok new-status)
  )
)

;; Add governance member
(define-public (add-governance-member (member principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set governance-members { address: member } { active: true })
    (ok true)
  )
)

;; Remove governance member
(define-public (remove-governance-member (member principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set governance-members { address: member } { active: false })
    (ok true)
  )
)

;; Set minimum governance approvals required
(define-public (set-min-governance-approvals (min-approvals uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (> min-approvals u0) ERR-INVALID-PARAMETER)
    (var-set min-governance-approvals min-approvals)
    (ok true)
  )
)

;; Set identity verifier
(define-public (set-identity-verifier (new-verifier principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set identity-verifier new-verifier)
    (ok true)
  )
)

;; Set achievement verifier
(define-public (set-achievement-verifier (new-verifier principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set achievement-verifier new-verifier)
    (ok true)
  )
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)