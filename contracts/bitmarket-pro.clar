;; Title: BitMarket Pro - Next-Gen Bitcoin Commerce Protocol
;;
;; Summary:
;; Revolutionary peer-to-peer marketplace leveraging Bitcoin's security through
;; Stacks L2 for instant settlements, zero-trust commerce, and global accessibility.
;;
;; Description:
;; BitMarket Pro transforms e-commerce by eliminating intermediaries and enabling
;; direct Bitcoin-settled transactions. Features trustless escrow, reputation-based
;; verification, dynamic auctions, and community-driven reviews - all secured by
;; Bitcoin's immutable blockchain while maintaining Lightning-fast transaction speeds.

;; CONSTANTS & ERROR CODES

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-brand-owner (err u101))
(define-constant err-invalid-price (err u102))
(define-constant err-listing-not-found (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-auction-ended (err u105))
(define-constant err-bid-too-low (err u106))
(define-constant err-no-active-auction (err u107))
(define-constant err-invalid-duration (err u108))
(define-constant err-invalid-rating (err u109))
(define-constant err-invalid-input (err u110))
(define-constant err-empty-string (err u111))

;; STATE VARIABLES

(define-data-var platform-fee uint u25) ;; 2.5% platform fee

;; DATA STRUCTURES

(define-map Brands
  principal
  {
    name: (string-ascii 50),
    verified: bool,
    created-at: uint,
  }
)

(define-map Products
  uint
  {
    brand: principal,
    name: (string-ascii 100),
    description: (string-ascii 500),
    price: uint,
    available: bool,
    created-at: uint,
    is-auction: bool,
  }
)

(define-map Auctions
  uint
  {
    end-block: uint,
    min-price: uint,
    highest-bid: uint,
    highest-bidder: (optional principal),
    is-active: bool,
  }
)

(define-map Reviews
  {
    product-id: uint,
    reviewer: principal,
  }
  {
    rating: uint,
    comment: (string-ascii 200),
    timestamp: uint,
  }
)

(define-data-var product-counter uint u0)

;; BRAND MANAGEMENT

;; Input validation helper
(define-private (is-valid-string (input (string-ascii 500)))
  (> (len input) u0)
)

;; Register new merchant brand
(define-public (register-brand (name (string-ascii 50)))
  (begin
    (asserts! (is-valid-string name) err-empty-string)
    (let ((brand-data {
        name: name,
        verified: false,
        created-at: stacks-block-height,
      }))
      (ok (map-set Brands tx-sender brand-data))
    )
  )
)

;; Platform verification for trusted merchants
(define-public (verify-brand (brand principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (let ((maybe-brand-data (map-get? Brands brand)))
      (match maybe-brand-data
        brand-data (ok (map-set Brands brand (merge brand-data { verified: true })))
        err-not-brand-owner
      )
    )
  )
)

;; DIRECT COMMERCE

;; Create instant-buy product listing
(define-public (list-product
    (name (string-ascii 100))
    (description (string-ascii 500))
    (price uint)
  )
  (let (
      (brand (unwrap! (map-get? Brands tx-sender) err-not-brand-owner))
      (product-id (+ (var-get product-counter) u1))
    )
    (asserts! (is-valid-string name) err-empty-string)
    (asserts! (is-valid-string description) err-empty-string)
    (asserts! (> price u0) err-invalid-price)

    (begin
      (var-set product-counter product-id)
      (ok (map-set Products product-id {
        brand: tx-sender,
        name: name,
        description: description,
        price: price,
        available: true,
        created-at: stacks-block-height,
        is-auction: false,
      }))
    )
  )
)

;; Execute Bitcoin-settled purchase
(define-public (purchase-product (product-id uint))
  (let (
      (product (unwrap! (map-get? Products product-id) err-listing-not-found))
      (price (get price product))
      (brand (get brand product))
      (fee (/ (* price (var-get platform-fee)) u1000))
    )
    (if (and
        (get available product)
        (not (get is-auction product))
        (>= (stx-get-balance tx-sender) price)
      )
      (begin
        (try! (stx-transfer? fee tx-sender contract-owner))
        (try! (stx-transfer? (- price fee) tx-sender brand))
        (map-set Products product-id (merge product { available: false }))
        (ok true)
      )
      err-insufficient-funds
    )
  )
)