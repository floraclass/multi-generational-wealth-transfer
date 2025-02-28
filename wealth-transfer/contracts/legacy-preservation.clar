;; legacy-preservation.clar
;; A smart contract for preserving family legacy and values

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-INITIALIZED (err u101))
(define-constant ERR-NOT-INITIALIZED (err u102))
(define-constant ERR-INVALID-VOTE (err u103))
(define-constant ERR-CAPSULE-NOT-FOUND (err u104))
(define-constant ERR-CAPSULE-NOT-UNLOCKED (err u105))
(define-constant ERR-INVALID-PARAMETER (err u106))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var constitution-hash (optional (buff 32)) none)

;; Data maps
(define-map family-members 
  { address: principal } 
  { active: bool }
)

(define-map value-alignment-votes
  { proposal-id: uint, member: principal }
  { aligned: bool }
)

(define-map value-alignment-proposals
  { proposal-id: uint }
  {
    description: (string-ascii 256),
    votes-for: uint,
    votes-against: uint,
    concluded: bool
  }
)

(define-map digital-time-capsules
  { capsule-id: uint }
  {
    title: (string-ascii 100),
    content-hash: (buff 32),
    unlock-condition: (string-ascii 100),
    unlocked: bool
  }
)

;; Variables
(define-data-var proposal-nonce uint u0)
(define-data-var capsule-nonce uint u0)

;; Read-only functions

(define-read-only (get-constitution-hash)
  (var-get constitution-hash)
)

(define-read-only (is-family-member (address principal))
  (default-to false (get active (map-get? family-members { address: address })))
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? value-alignment-proposals { proposal-id: proposal-id })
)

(define-read-only (get-vote (proposal-id uint) (member principal))
  (map-get? value-alignment-votes { proposal-id: proposal-id, member: member })
)

(define-read-only (get-time-capsule (capsule-id uint))
  (map-get? digital-time-capsules { capsule-id: capsule-id })
)

;; Public functions

;; Initialize the contract with the family constitution
(define-public (initialize-constitution (new-constitution-hash (buff 32)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (var-get constitution-hash)) ERR-ALREADY-INITIALIZED)
    (var-set constitution-hash (some new-constitution-hash))
    (ok true)
  )
)

;; Add a family member
(define-public (add-family-member (address principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set family-members { address: address } { active: true })
    (ok true)
  )
)

;; Remove a family member
(define-public (remove-family-member (address principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set family-members { address: address } { active: false })
    (ok true)
  )
)

;; Create a new value alignment proposal
(define-public (create-value-proposal (description (string-ascii 256)))
  (let
    (
      (proposal-id (+ (var-get proposal-nonce) u1))
    )
    (asserts! (is-family-member tx-sender) ERR-NOT-AUTHORIZED)
    (map-set value-alignment-proposals
      { proposal-id: proposal-id }
      {
        description: description,
        votes-for: u0,
        votes-against: u0,
        concluded: false
      }
    )
    (var-set proposal-nonce proposal-id)
    (ok proposal-id)
  )
)

;; Vote on a value alignment proposal
(define-public (vote-on-proposal (proposal-id uint) (aligned bool))
  (let
    (
      (proposal (unwrap! (get-proposal proposal-id) ERR-INVALID-VOTE))
    )
    (asserts! (is-family-member tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (get concluded proposal)) ERR-INVALID-VOTE)
    (asserts! (is-none (get-vote proposal-id tx-sender)) ERR-INVALID-VOTE)
    
    (map-set value-alignment-votes
      { proposal-id: proposal-id, member: tx-sender }
      { aligned: aligned }
    )
    
    (map-set value-alignment-proposals
      { proposal-id: proposal-id }
      (merge proposal
        {
          votes-for: (if aligned (+ (get votes-for proposal) u1) (get votes-for proposal)),
          votes-against: (if aligned (get votes-against proposal) (+ (get votes-against proposal) u1))
        }
      )
    )
    (ok true)
  )
)

;; Conclude a value alignment proposal
(define-public (conclude-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (get-proposal proposal-id) ERR-INVALID-VOTE))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get concluded proposal)) ERR-INVALID-VOTE)
    
    (map-set value-alignment-proposals
      { proposal-id: proposal-id }
      (merge proposal { concluded: true })
    )
    (ok true)
  )
)

;; Create a new digital time capsule
(define-public (create-time-capsule (title (string-ascii 100)) (content-hash (buff 32)) (unlock-condition (string-ascii 100)))
  (let
    (
      (capsule-id (+ (var-get capsule-nonce) u1))
    )
    (asserts! (is-family-member tx-sender) ERR-NOT-AUTHORIZED)
    (map-set digital-time-capsules
      { capsule-id: capsule-id }
      {
        title: title,
        content-hash: content-hash,
        unlock-condition: unlock-condition,
        unlocked: false
      }
    )
    (var-set capsule-nonce capsule-id)
    (ok capsule-id)
  )
)

;; Unlock a digital time capsule
(define-public (unlock-time-capsule (capsule-id uint))
  (let
    (
      (capsule (unwrap! (get-time-capsule capsule-id) ERR-CAPSULE-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get unlocked capsule)) ERR-CAPSULE-NOT-UNLOCKED)
    
    (map-set digital-time-capsules
      { capsule-id: capsule-id }
      (merge capsule { unlocked: true })
    )
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