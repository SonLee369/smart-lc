;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 
;; Simple Letter of Credit (MVP)
;; Focus: Atomic Escrow & Settlement on Stacks
;; Pain Killer: Guarantees payment release upon verification.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 

;; --- Constants -----------------------------------------------------------------
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATUS (err u102))
(define-constant ERR-ALREADY-SUBMITTED (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))

(define-constant STATUS-FUNDED u0)
(define-constant STATUS-DOCS-SUBMITTED u1)
(define-constant STATUS-PAID u2)
(define-constant STATUS-CANCELLED u3)

;; --- Data Storage --------------------------------------------------------------
(define-map letters-of-credit
    uint
    {
        importer: principal,
        exporter: principal,
        verifier: principal, ;; The trusted entity (bank) who can release payment
        amount: uint,
        status: uint,
        documents-hash: (optional (buff 32)),
    }
)

(define-data-var lc-counter uint u0)

;; --- Public Functions ----------------------------------------------------------

;; @desc Importer creates and funds the L/C, locking STX in the contract.
;; @param exporter; The seller who will receive the funds.
;; @param verifier; The bank/agent who can approve payment.
;; @param amount; The value of the L/C in micro-STX.
(define-public (create-lc
        (exporter principal)
        (verifier principal)
        (amount uint)
    )
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)

        ;; Lock the funds by transferring STX from the importer to this contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

        (let ((lc-id (+ (var-get lc-counter) u1)))
            (map-set letters-of-credit lc-id {
                importer: tx-sender,
                exporter: exporter,
                verifier: verifier,
                amount: amount,
                status: STATUS-FUNDED,
                documents-hash: none,
            })
            (var-set lc-counter lc-id)
            (ok lc-id)
        )
    )
)

;; @desc Exporter submits a hash of their shipping documents.
(define-public (submit-documents
        (lc-id uint)
        (hash (buff 32))
    )
    (let ((lc (unwrap! (map-get? letters-of-credit lc-id) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get exporter lc)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status lc) STATUS-FUNDED) ERR-INVALID-STATUS)
        (asserts! (is-none (get documents-hash lc)) ERR-ALREADY-SUBMITTED)

        (map-set letters-of-credit lc-id
            (merge lc {
                documents-hash: (some hash),
                status: STATUS-DOCS-SUBMITTED,
            })
        )
        (ok true)
    )
)

;; @desc The Verifier confirms docs are valid and releases payment to the Exporter.
;; THIS IS THE CORE PAIN-KILLER FUNCTION.
(define-public (verify-and-release-payment (lc-id uint))
    (let ((lc (unwrap! (map-get? letters-of-credit lc-id) ERR-NOT-FOUND)))
        ;; Guards: only the verifier can call this on a submitted LC
        (asserts! (is-eq tx-sender (get verifier lc)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status lc) STATUS-DOCS-SUBMITTED)
            ERR-INVALID-STATUS
        )

        ;; Action: Transfer the locked STX from the contract to the exporter
        (try! (as-contract (stx-transfer? (get amount lc) tx-sender (get exporter lc))))

        ;; Update status to PAID
        (map-set letters-of-credit lc-id (merge lc { status: STATUS-PAID }))
        (ok true)
    )
)

;; @desc Importer can cancel and reclaim funds *only if* docs haven't been submitted.
(define-public (cancel-lc (lc-id uint))
    (let ((lc (unwrap! (map-get? letters-of-credit lc-id) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get importer lc)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status lc) STATUS-FUNDED) ERR-INVALID-STATUS)

        ;; Return funds from contract back to importer
        (try! (as-contract (stx-transfer? (get amount lc) tx-sender (get importer lc))))

        (map-set letters-of-credit lc-id (merge lc { status: STATUS-CANCELLED }))
        (ok true)
    )
)

;; --- Read-Only Functions -------------------------------------------------------

;; @desc View the details of a specific Letter of Credit.
(define-read-only (get-lc (lc-id uint))
    (map-get? letters-of-credit lc-id)
)
