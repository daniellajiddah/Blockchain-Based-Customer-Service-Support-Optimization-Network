;; Satisfaction Measurement Contract
;; Measures customer satisfaction

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-RATED (err u103))

;; Data Variables
(define-data-var next-feedback-id uint u1)

;; Data Maps
(define-map customer-feedback
  { feedback-id: uint }
  {
    ticket-id: uint,
    customer: principal,
    manager-id: uint,
    satisfaction-score: uint,
    response-time-rating: uint,
    solution-quality-rating: uint,
    communication-rating: uint,
    overall-experience: uint,
    comments: (string-ascii 400),
    would-recommend: bool,
    created-at: uint
  }
)

(define-map ticket-feedback
  { ticket-id: uint }
  { feedback-id: uint }
)

(define-map manager-satisfaction-stats
  { manager-id: uint }
  {
    total-feedback: uint,
    average-satisfaction: uint,
    average-response-time: uint,
    average-solution-quality: uint,
    average-communication: uint,
    recommendation-rate: uint,
    last-feedback-date: uint
  }
)

(define-map satisfaction-trends
  { period: uint }
  {
    total-responses: uint,
    average-satisfaction: uint,
    trend-direction: (string-ascii 10),
    period-start: uint,
    period-end: uint
  }
)

(define-map customer-history
  { customer: principal }
  {
    total-tickets: uint,
    feedback-given: uint,
    average-satisfaction: uint,
    last-interaction: uint
  }
)

;; Public Functions

;; Submit customer feedback
(define-public (submit-feedback
  (ticket-id uint)
  (manager-id uint)
  (satisfaction-score uint)
  (response-time-rating uint)
  (solution-quality-rating uint)
  (communication-rating uint)
  (comments (string-ascii 400))
  (would-recommend bool)
)
  (let
    (
      (feedback-id (var-get next-feedback-id))
      (customer tx-sender)
      (overall-experience (/ (+ satisfaction-score response-time-rating solution-quality-rating communication-rating) u4))
    )
    (asserts! (is-none (map-get? ticket-feedback { ticket-id: ticket-id })) ERR-ALREADY-RATED)
    (asserts! (<= satisfaction-score u5) ERR-INVALID-INPUT)
    (asserts! (<= response-time-rating u5) ERR-INVALID-INPUT)
    (asserts! (<= solution-quality-rating u5) ERR-INVALID-INPUT)
    (asserts! (<= communication-rating u5) ERR-INVALID-INPUT)

    (map-set customer-feedback
      { feedback-id: feedback-id }
      {
        ticket-id: ticket-id,
        customer: customer,
        manager-id: manager-id,
        satisfaction-score: satisfaction-score,
        response-time-rating: response-time-rating,
        solution-quality-rating: solution-quality-rating,
        communication-rating: communication-rating,
        overall-experience: overall-experience,
        comments: comments,
        would-recommend: would-recommend,
        created-at: block-height
      }
    )

    (map-set ticket-feedback
      { ticket-id: ticket-id }
      { feedback-id: feedback-id }
    )

    (unwrap! (update-manager-satisfaction-stats manager-id satisfaction-score response-time-rating solution-quality-rating communication-rating would-recommend) ERR-INVALID-INPUT)
    (unwrap! (update-customer-history customer satisfaction-score) ERR-INVALID-INPUT)

    (var-set next-feedback-id (+ feedback-id u1))
    (ok feedback-id)
  )
)

;; Update satisfaction trends
(define-public (update-satisfaction-trends (period uint))
  (let
    (
      (current-trend (default-to
        { total-responses: u0, average-satisfaction: u0, trend-direction: "stable", period-start: u0, period-end: u0 }
        (map-get? satisfaction-trends { period: period })
      ))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)

    (map-set satisfaction-trends
      { period: period }
      {
        total-responses: (get total-responses current-trend),
        average-satisfaction: (get average-satisfaction current-trend),
        trend-direction: "stable",
        period-start: block-height,
        period-end: (+ block-height u144)
      }
    )
    (ok true)
  )
)

;; Generate satisfaction report
(define-public (generate-satisfaction-report (manager-id uint))
  (let
    (
      (stats (unwrap! (map-get? manager-satisfaction-stats { manager-id: manager-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)

    (ok {
      manager-id: manager-id,
      total-feedback: (get total-feedback stats),
      satisfaction-score: (get average-satisfaction stats),
      performance-rating: (if (>= (get average-satisfaction stats) u4) "excellent"
        (if (>= (get average-satisfaction stats) u3) "good"
          (if (>= (get average-satisfaction stats) u2) "fair" "poor")
        )
      ),
      recommendation-rate: (get recommendation-rate stats),
      generated-at: block-height
    })
  )
)

;; Private Functions

;; Update manager satisfaction statistics
(define-private (update-manager-satisfaction-stats
  (manager-id uint)
  (satisfaction uint)
  (response-time uint)
  (solution-quality uint)
  (communication uint)
  (would-recommend bool)
)
  (let
    (
      (current-stats (default-to
        { total-feedback: u0, average-satisfaction: u0, average-response-time: u0, average-solution-quality: u0, average-communication: u0, recommendation-rate: u0, last-feedback-date: u0 }
        (map-get? manager-satisfaction-stats { manager-id: manager-id })
      ))
      (new-total (+ (get total-feedback current-stats) u1))
      (new-avg-satisfaction (/ (+ (* (get average-satisfaction current-stats) (get total-feedback current-stats)) satisfaction) new-total))
      (new-avg-response (/ (+ (* (get average-response-time current-stats) (get total-feedback current-stats)) response-time) new-total))
      (new-avg-solution (/ (+ (* (get average-solution-quality current-stats) (get total-feedback current-stats)) solution-quality) new-total))
      (new-avg-comm (/ (+ (* (get average-communication current-stats) (get total-feedback current-stats)) communication) new-total))
      (recommendation-count (if would-recommend
        (+ (* (get recommendation-rate current-stats) (get total-feedback current-stats)) u100)
        (* (get recommendation-rate current-stats) (get total-feedback current-stats))
      ))
      (new-recommendation-rate (/ recommendation-count new-total))
    )
    (map-set manager-satisfaction-stats
      { manager-id: manager-id }
      {
        total-feedback: new-total,
        average-satisfaction: new-avg-satisfaction,
        average-response-time: new-avg-response,
        average-solution-quality: new-avg-solution,
        average-communication: new-avg-comm,
        recommendation-rate: new-recommendation-rate,
        last-feedback-date: block-height
      }
    )
    (ok true)
  )
)

;; Update customer history
(define-private (update-customer-history (customer principal) (satisfaction uint))
  (let
    (
      (current-history (default-to
        { total-tickets: u0, feedback-given: u0, average-satisfaction: u0, last-interaction: u0 }
        (map-get? customer-history { customer: customer })
      ))
      (new-feedback-count (+ (get feedback-given current-history) u1))
      (new-avg-satisfaction (/ (+ (* (get average-satisfaction current-history) (get feedback-given current-history)) satisfaction) new-feedback-count))
    )
    (map-set customer-history
      { customer: customer }
      {
        total-tickets: (get total-tickets current-history),
        feedback-given: new-feedback-count,
        average-satisfaction: new-avg-satisfaction,
        last-interaction: block-height
      }
    )
    (ok true)
  )
)

;; Read-Only Functions

;; Get customer feedback
(define-read-only (get-customer-feedback (feedback-id uint))
  (map-get? customer-feedback { feedback-id: feedback-id })
)

;; Get feedback by ticket
(define-read-only (get-feedback-by-ticket (ticket-id uint))
  (match (map-get? ticket-feedback { ticket-id: ticket-id })
    feedback-data (map-get? customer-feedback { feedback-id: (get feedback-id feedback-data) })
    none
  )
)

;; Get manager satisfaction stats
(define-read-only (get-manager-satisfaction-stats (manager-id uint))
  (map-get? manager-satisfaction-stats { manager-id: manager-id })
)

;; Get satisfaction trends
(define-read-only (get-satisfaction-trends (period uint))
  (map-get? satisfaction-trends { period: period })
)

;; Get customer history
(define-read-only (get-customer-history (customer principal))
  (map-get? customer-history { customer: customer })
)

;; Calculate satisfaction level
(define-read-only (get-satisfaction-level (score uint))
  (if (>= score u5) "excellent"
    (if (>= score u4) "very-good"
      (if (>= score u3) "good"
        (if (>= score u2) "fair" "poor")
      )
    )
  )
)

;; Get total feedback count
(define-read-only (get-total-feedback)
  (- (var-get next-feedback-id) u1)
)

;; Check if ticket has feedback
(define-read-only (has-feedback (ticket-id uint))
  (is-some (map-get? ticket-feedback { ticket-id: ticket-id }))
)
