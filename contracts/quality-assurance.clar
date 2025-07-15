;; Quality Assurance Contract
;; Ensures support quality through reviews

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-REVIEWED (err u103))

;; Data Variables
(define-data-var next-review-id uint u1)

;; Data Maps
(define-map quality-reviews
  { review-id: uint }
  {
    ticket-id: uint,
    manager-id: uint,
    reviewer: principal,
    communication-score: uint,
    technical-score: uint,
    timeliness-score: uint,
    overall-score: uint,
    feedback: (string-ascii 300),
    improvement-areas: (string-ascii 200),
    created-at: uint
  }
)

(define-map ticket-reviews
  { ticket-id: uint }
  { review-id: uint }
)

(define-map manager-quality-stats
  { manager-id: uint }
  {
    total-reviews: uint,
    average-communication: uint,
    average-technical: uint,
    average-timeliness: uint,
    overall-quality-score: uint,
    improvement-count: uint,
    last-review-date: uint
  }
)

(define-map quality-standards
  { category: (string-ascii 30) }
  {
    min-communication-score: uint,
    min-technical-score: uint,
    min-timeliness-score: uint,
    min-overall-score: uint,
    review-frequency: uint
  }
)

(define-map reviewer-permissions
  { reviewer: principal }
  {
    can-review: bool,
    categories: (list 5 (string-ascii 30)),
    review-count: uint,
    added-by: principal,
    added-at: uint
  }
)

;; Public Functions

;; Add quality reviewer
(define-public (add-reviewer (reviewer principal) (categories (list 5 (string-ascii 30))))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? reviewer-permissions { reviewer: reviewer })) ERR-ALREADY-REVIEWED)

    (map-set reviewer-permissions
      { reviewer: reviewer }
      {
        can-review: true,
        categories: categories,
        review-count: u0,
        added-by: tx-sender,
        added-at: block-height
      }
    )
    (ok true)
  )
)

;; Create quality review
(define-public (create-quality-review
  (ticket-id uint)
  (manager-id uint)
  (communication-score uint)
  (technical-score uint)
  (timeliness-score uint)
  (feedback (string-ascii 300))
  (improvement-areas (string-ascii 200))
)
  (let
    (
      (review-id (var-get next-review-id))
      (reviewer-perms (unwrap! (map-get? reviewer-permissions { reviewer: tx-sender }) ERR-UNAUTHORIZED))
      (overall-score (/ (+ communication-score technical-score timeliness-score) u3))
    )
    (asserts! (get can-review reviewer-perms) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? ticket-reviews { ticket-id: ticket-id })) ERR-ALREADY-REVIEWED)
    (asserts! (<= communication-score u5) ERR-INVALID-INPUT)
    (asserts! (<= technical-score u5) ERR-INVALID-INPUT)
    (asserts! (<= timeliness-score u5) ERR-INVALID-INPUT)

    (map-set quality-reviews
      { review-id: review-id }
      {
        ticket-id: ticket-id,
        manager-id: manager-id,
        reviewer: tx-sender,
        communication-score: communication-score,
        technical-score: technical-score,
        timeliness-score: timeliness-score,
        overall-score: overall-score,
        feedback: feedback,
        improvement-areas: improvement-areas,
        created-at: block-height
      }
    )

    (map-set ticket-reviews
      { ticket-id: ticket-id }
      { review-id: review-id }
    )

    (unwrap! (update-manager-quality-stats manager-id communication-score technical-score timeliness-score overall-score) ERR-INVALID-INPUT)
    (unwrap! (update-reviewer-count tx-sender) ERR-INVALID-INPUT)

    (var-set next-review-id (+ review-id u1))
    (ok review-id)
  )
)

;; Set quality standards
(define-public (set-quality-standards
  (category (string-ascii 30))
  (min-communication uint)
  (min-technical uint)
  (min-timeliness uint)
  (min-overall uint)
  (review-frequency uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= min-communication u5) ERR-INVALID-INPUT)
    (asserts! (<= min-technical u5) ERR-INVALID-INPUT)
    (asserts! (<= min-timeliness u5) ERR-INVALID-INPUT)
    (asserts! (<= min-overall u5) ERR-INVALID-INPUT)

    (map-set quality-standards
      { category: category }
      {
        min-communication-score: min-communication,
        min-technical-score: min-technical,
        min-timeliness-score: min-timeliness,
        min-overall-score: min-overall,
        review-frequency: review-frequency
      }
    )
    (ok true)
  )
)

;; Update reviewer permissions
(define-public (update-reviewer-permissions (reviewer principal) (can-review bool))
  (let
    (
      (current-perms (unwrap! (map-get? reviewer-permissions { reviewer: reviewer }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)

    (map-set reviewer-permissions
      { reviewer: reviewer }
      (merge current-perms { can-review: can-review })
    )
    (ok true)
  )
)

;; Private Functions

;; Update manager quality statistics
(define-private (update-manager-quality-stats (manager-id uint) (comm-score uint) (tech-score uint) (time-score uint) (overall-score uint))
  (let
    (
      (current-stats (default-to
        { total-reviews: u0, average-communication: u0, average-technical: u0, average-timeliness: u0, overall-quality-score: u0, improvement-count: u0, last-review-date: u0 }
        (map-get? manager-quality-stats { manager-id: manager-id })
      ))
      (new-total (+ (get total-reviews current-stats) u1))
      (new-avg-comm (/ (+ (* (get average-communication current-stats) (get total-reviews current-stats)) comm-score) new-total))
      (new-avg-tech (/ (+ (* (get average-technical current-stats) (get total-reviews current-stats)) tech-score) new-total))
      (new-avg-time (/ (+ (* (get average-timeliness current-stats) (get total-reviews current-stats)) time-score) new-total))
      (new-overall (/ (+ (* (get overall-quality-score current-stats) (get total-reviews current-stats)) overall-score) new-total))
      (needs-improvement (< overall-score u3))
    )
    (map-set manager-quality-stats
      { manager-id: manager-id }
      {
        total-reviews: new-total,
        average-communication: new-avg-comm,
        average-technical: new-avg-tech,
        average-timeliness: new-avg-time,
        overall-quality-score: new-overall,
        improvement-count: (if needs-improvement
          (+ (get improvement-count current-stats) u1)
          (get improvement-count current-stats)
        ),
        last-review-date: block-height
      }
    )
    (ok true)
  )
)

;; Update reviewer count
(define-private (update-reviewer-count (reviewer principal))
  (let
    (
      (current-perms (unwrap! (map-get? reviewer-permissions { reviewer: reviewer }) ERR-NOT-FOUND))
    )
    (map-set reviewer-permissions
      { reviewer: reviewer }
      (merge current-perms {
        review-count: (+ (get review-count current-perms) u1)
      })
    )
    (ok true)
  )
)

;; Read-Only Functions

;; Get quality review
(define-read-only (get-quality-review (review-id uint))
  (map-get? quality-reviews { review-id: review-id })
)

;; Get review by ticket
(define-read-only (get-review-by-ticket (ticket-id uint))
  (match (map-get? ticket-reviews { ticket-id: ticket-id })
    review-data (map-get? quality-reviews { review-id: (get review-id review-data) })
    none
  )
)

;; Get manager quality stats
(define-read-only (get-manager-quality-stats (manager-id uint))
  (map-get? manager-quality-stats { manager-id: manager-id })
)

;; Get quality standards
(define-read-only (get-quality-standards (category (string-ascii 30)))
  (map-get? quality-standards { category: category })
)

;; Get reviewer permissions
(define-read-only (get-reviewer-permissions (reviewer principal))
  (map-get? reviewer-permissions { reviewer: reviewer })
)

;; Check if manager meets quality standards
(define-read-only (meets-quality-standards (manager-id uint) (category (string-ascii 30)))
  (match (map-get? manager-quality-stats { manager-id: manager-id })
    stats (match (map-get? quality-standards { category: category })
      standards (and
        (>= (get average-communication stats) (get min-communication-score standards))
        (>= (get average-technical stats) (get min-technical-score standards))
        (>= (get average-timeliness stats) (get min-timeliness-score standards))
        (>= (get overall-quality-score stats) (get min-overall-score standards))
      )
      false
    )
    false
  )
)

;; Get total reviews
(define-read-only (get-total-reviews)
  (- (var-get next-review-id) u1)
)
