;; legacy-integration.clar
;; A smart contract for integrating blockchain legacy with traditional systems

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PARAMETER (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-ORACLE-FAILURE (err u104))
(define-constant ERR-CONVERSION-FAILURE (err u105))
(define-constant ERR-INTEGRATION-FAILURE (err u106))
(define-constant ERR-INVALID-STATUS (err u107))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var oracle-provider principal tx-sender)
(define-data-var conversion-provider principal tx-sender)

;; Data maps
(define-map traditional-estate-integrations
  { integration-id: uint }
  {
    estate-type: (string-ascii 20), ;; "trust", "will", "foundation", etc.
    legal-identifier: (string-ascii 100),
    jurisdiction: (string-ascii 50),
    status: (string-ascii 20), ;; "active", "pending", "revoked"
    metadata-uri: (optional (string-utf8 256))
  }
)

(define-map jurisdiction-compliance
  { jurisdiction: (string-ascii 50) }
  {
    compliance-hash: (buff 32),
    last-updated: uint,
    is-compliant: bool,
    requirements-uri: (string-utf8 256)
  }
)

(define-map fiat-crypto-conversions
  { conversion-id: uint }
  {
    fiat-type: (string-ascii 10), ;; "USD", "EUR", etc.
    fiat-amount: uint,
    crypto-type: (string-ascii 10), ;; "STX", "BTC", etc.
    crypto-amount: uint,
    status: (string-ascii 20), ;; "pending", "completed", "failed"
    timestamp: uint
  }
)

(define-map asset-mappings
  { asset-id: uint }
  {
    traditional-description: (string-ascii 100),
    blockchain-representation: (string-ascii 100),
    valuation-usd: uint,
    last-updated: uint
  }
)

;; Variables
(define-data-var integration-nonce uint u0)
(define-data-var conversion-nonce uint u0)
(define-data-var asset-nonce uint u0)

;; Read-only functions

(define-read-only (get-estate-integration (integration-id uint))
  (map-get? traditional-estate-integrations { integration-id: integration-id })
)

(define-read-only (get-jurisdiction-compliance (jurisdiction (string-ascii 50)))
  (map-get? jurisdiction-compliance { jurisdiction: jurisdiction })
)

(define-read-only (get-conversion (conversion-id uint))
  (map-get? fiat-crypto-conversions { conversion-id: conversion-id })
)

(define-read-only (get-asset-mapping (asset-id uint))
  (map-get? asset-mappings { asset-id: asset-id })
)

;; Public functions

;; Register a traditional estate integration
(define-public (register-estate-integration 
    (estate-type (string-ascii 20)) 
    (legal-identifier (string-ascii 100))
    (jurisdiction (string-ascii 50))
    (metadata-uri (optional (string-utf8 256))))
  (let
    (
      (integration-id (+ (var-get integration-nonce) u1))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    
    ;; Check if jurisdiction is compliant
    (asserts! 
      (default-to 
        false 
        (get is-compliant (map-get? jurisdiction-compliance { jurisdiction: jurisdiction }))
      ) 
      ERR-INVALID-PARAMETER
    )
    
    (map-set traditional-estate-integrations
      { integration-id: integration-id }
      {
        estate-type: estate-type,
        legal-identifier: legal-identifier,
        jurisdiction: jurisdiction,
        status: "pending",
        metadata-uri: metadata-uri
      }
    )
    (var-set integration-nonce integration-id)
    (ok integration-id)
  )
)

;; Update estate integration status
(define-public (update-estate-status (integration-id uint) (new-status (string-ascii 20)))
  (let
    (
      (integration (unwrap! (get-estate-integration integration-id) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! 
      (or 
        (is-eq new-status "active") 
        (is-eq new-status "pending") 
        (is-eq new-status "revoked")
      ) 
      ERR-INVALID-PARAMETER
    )
    
    (map-set traditional-estate-integrations
      { integration-id: integration-id }
      (merge integration { status: new-status })
    )
    (ok true)
  )
)

;; Update jurisdiction compliance data via oracle
(define-public (update-jurisdiction-compliance 
    (jurisdiction (string-ascii 50))
    (compliance-hash (buff 32))
    (is-compliant bool)
    (requirements-uri (string-utf8 256)))
  (begin
    (asserts! (is-eq tx-sender (var-get oracle-provider)) ERR-NOT-AUTHORIZED)
    
    (map-set jurisdiction-compliance
      { jurisdiction: jurisdiction }
      {
        compliance-hash: compliance-hash,
        last-updated: stacks-block-height,
        is-compliant: is-compliant,
        requirements-uri: requirements-uri
      }
    )
    (ok true)
  )
)

;; Initiate fiat-to-crypto conversion
(define-public (initiate-conversion 
    (fiat-type (string-ascii 10))
    (fiat-amount uint)
    (crypto-type (string-ascii 10)))
  (let
    (
      (conversion-id (+ (var-get conversion-nonce) u1))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    
    (map-set fiat-crypto-conversions
      { conversion-id: conversion-id }
      {
        fiat-type: fiat-type,
        fiat-amount: fiat-amount,
        crypto-type: crypto-type,
        crypto-amount: u0, ;; Will be updated by conversion provider
        status: "pending",
        timestamp: stacks-block-height
      }
    )
    (var-set conversion-nonce conversion-id)
    (ok conversion-id)
  )
)

;; Complete fiat-to-crypto conversion (called by conversion provider)
(define-public (complete-conversion 
    (conversion-id uint)
    (crypto-amount uint)
    (status (string-ascii 20)))
  (let
    (
      (conversion (unwrap! (get-conversion conversion-id) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get conversion-provider)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status conversion) "pending") ERR-INVALID-STATUS)
    (asserts! 
      (or 
        (is-eq status "completed") 
        (is-eq status "failed")
      ) 
      ERR-INVALID-PARAMETER
    )
    
    (map-set fiat-crypto-conversions
      { conversion-id: conversion-id }
      (merge conversion 
        { 
          crypto-amount: crypto-amount,
          status: status
        }
      )
    )
    (ok true)
  )
)

;; Register traditional asset mapping to blockchain representation
(define-public (register-asset-mapping
    (traditional-description (string-ascii 100))
    (blockchain-representation (string-ascii 100))
    (valuation-usd uint))
  (let
    (
      (asset-id (+ (var-get asset-nonce) u1))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    
    (map-set asset-mappings
      { asset-id: asset-id }
      {
        traditional-description: traditional-description,
        blockchain-representation: blockchain-representation,
        valuation-usd: valuation-usd,
        last-updated: stacks-block-height
      }
    )
    (var-set asset-nonce asset-id)
    (ok asset-id)
  )
)

;; Update asset valuation
(define-public (update-asset-valuation (asset-id uint) (new-valuation-usd uint))
  (let
    (
      (asset (unwrap! (get-asset-mapping asset-id) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    
    (map-set asset-mappings
      { asset-id: asset-id }
      (merge asset 
        { 
          valuation-usd: new-valuation-usd,
          last-updated: stacks-block-height
        }
      )
    )
    (ok true)
  )
)

;; Set oracle provider
(define-public (set-oracle-provider (new-provider principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set oracle-provider new-provider)
    (ok true)
  )
)

;; Set conversion provider
(define-public (set-conversion-provider (new-provider principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set conversion-provider new-provider)
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