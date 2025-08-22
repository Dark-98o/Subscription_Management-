;; Subscription Management Contract
;; A smart contract for managing recurring payment subscriptions
;; Supports subscription creation and payment processing

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-subscription-not-found (err u101))
(define-constant err-subscription-expired (err u102))
(define-constant err-insufficient-payment (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-subscription-exists (err u105))

;; Data structures
(define-map subscriptions
  { subscriber: principal }
  { 
    amount: uint,
    duration: uint,
    start-block: uint,
    last-payment-block: uint,
    is-active: bool
  })

(define-data-var total-revenue uint u0)

;; Function 1: Create Subscription
;; Creates a new subscription for a user with specified amount and duration
(define-public (create-subscription (amount uint) (duration uint))
  (begin
    ;; Validate inputs
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (> duration u0) err-invalid-amount)
    
    ;; Check if subscription already exists for this user
    (asserts! (is-none (map-get? subscriptions { subscriber: tx-sender })) err-subscription-exists)
    
    ;; Create the subscription
    (map-set subscriptions 
      { subscriber: tx-sender }
      { 
        amount: amount,
        duration: duration,
        start-block: stacks-block-height,
        last-payment-block: stacks-block-height,
        is-active: true
      })
    
    ;; Process initial payment
    (try! (stx-transfer? amount tx-sender contract-owner))
    (var-set total-revenue (+ (var-get total-revenue) amount))
    
    (print { event: "subscription-created", subscriber: tx-sender, amount: amount, duration: duration })
    (ok true)))

;; Function 2: Process Recurring Payment
;; Processes a recurring payment for an existing subscription
(define-public (process-payment)
  (let 
    (
      (subscription-data (unwrap! (map-get? subscriptions { subscriber: tx-sender }) err-subscription-not-found))
      (current-block stacks-block-height)
      (last-payment (get last-payment-block subscription-data))
      (duration (get duration subscription-data))
      (amount (get amount subscription-data))
      (is-active (get is-active subscription-data))
    )
    
    ;; Check if subscription is active
    (asserts! is-active err-subscription-expired)
    
    ;; Check if enough time has passed since last payment (duration in blocks)
    (asserts! (>= (- current-block last-payment) duration) err-subscription-expired)
    
    ;; Process the payment
    (try! (stx-transfer? amount tx-sender contract-owner))
    
    ;; Update subscription data
    (map-set subscriptions
      { subscriber: tx-sender }
      (merge subscription-data { last-payment-block: current-block }))
    
    ;; Update total revenue
    (var-set total-revenue (+ (var-get total-revenue) amount))
    
    (print { event: "payment-processed", subscriber: tx-sender, amount: amount, block: current-block })
    (ok true)))

;; Read-only functions for data retrieval
(define-read-only (get-subscription (subscriber principal))
  (ok (map-get? subscriptions { subscriber: subscriber })))

(define-read-only (get-total-revenue)
  (ok (var-get total-revenue)))

(define-read-only (is-payment-due (subscriber principal))
  (match (map-get? subscriptions { subscriber: subscriber })
    subscription-data 
    (let 
      (
        (current-block stacks-block-height)
        (last-payment (get last-payment-block subscription-data))
        (duration (get duration subscription-data))
        (is-active (get is-active subscription-data))
      )
      (ok (and is-active (>= (- current-block last-payment) duration))))
    (ok false)))