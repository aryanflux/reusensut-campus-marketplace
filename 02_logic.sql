-- ReUseNSUT : File 2 of 4 : views, triggers and stored procedures
USE reusensut;
-- VIEWS
-- Trust score (0-100) = 14 x average rating (max 70)
--                     + 3 x on-time returns (counted up to 10, max 30)
--                     - 5 x late returns.     No reviews yet => neutral rating of 3.
CREATE VIEW v_trust_scores AS
SELECT u.user_id,
       u.name,
       ROUND(COALESCE(r.avg_rating, 3), 2)  AS avg_rating,
       COALESCE(r.review_count, 0)          AS review_count,
       COALESCE(l.on_time, 0)               AS on_time_returns,
       COALESCE(l.late, 0)                  AS late_returns,
       ROUND(GREATEST(0, LEAST(100,
             14 * COALESCE(r.avg_rating, 3)
           + 3  * LEAST(COALESCE(l.on_time, 0), 10)
           - 5  * COALESCE(l.late, 0))), 1) AS trust_score
FROM users u
LEFT JOIN (SELECT reviewee_id, AVG(rating) AS avg_rating, COUNT(*) AS review_count
           FROM reviews GROUP BY reviewee_id) r ON r.reviewee_id = u.user_id
LEFT JOIN (SELECT rq.requester_id AS user_id,
                  SUM(DATE(lo.returned_at) <= lo.due_date) AS on_time,
                  SUM(DATE(lo.returned_at) >  lo.due_date) AS late
           FROM loans lo
           JOIN transactions t      ON t.transaction_id = lo.transaction_id
           JOIN listing_requests rq ON rq.request_id    = t.request_id
           WHERE lo.returned_at IS NOT NULL
           GROUP BY rq.requester_id) l ON l.user_id = u.user_id
WHERE u.account_role = 'student';

CREATE VIEW v_available_listings AS
SELECT l.listing_id, i.item_id, i.item_name, c.category_name, l.listing_type,
       l.price, l.deposit_amount, l.max_loan_days, i.item_condition, i.semester,
       o.user_id AS owner_id, o.name AS owner_name, o.branch AS owner_branch,
       ts.trust_score AS owner_trust_score, l.expiry_date
FROM listings l
JOIN items i       ON i.item_id     = l.item_id
JOIN categories c  ON c.category_id = i.category_id
JOIN users o       ON o.user_id     = i.owner_id
JOIN v_trust_scores ts ON ts.user_id = o.user_id
WHERE l.listing_status = 'active'
  AND (l.expiry_date IS NULL OR l.expiry_date >= CURDATE());

CREATE VIEW v_listing_requests AS
SELECT r.request_id, l.listing_id, i.owner_id, i.item_name, l.listing_type,
       rq.user_id AS requester_id, rq.name AS requester_name, rq.branch AS requester_branch,
       ts.trust_score AS requester_trust_score,
       oi.item_name AS offered_item, r.request_message, r.requested_at, r.request_status
FROM listing_requests r
JOIN listings l  ON l.listing_id = r.listing_id
JOIN items i     ON i.item_id    = l.item_id
JOIN users rq    ON rq.user_id   = r.requester_id
JOIN v_trust_scores ts ON ts.user_id = rq.user_id
LEFT JOIN items oi ON oi.item_id = r.offered_item_id;

CREATE VIEW v_loan_details AS
SELECT lo.transaction_id, i.item_id, i.item_name,
       b.user_id AS borrower_id, b.name AS borrower_name, b.phone AS borrower_phone,
       o.user_id AS owner_id,    o.name AS owner_name,
       lo.borrowed_at, lo.due_date, lo.returned_at, lo.loan_status, lo.returned_good_condition,
       p.amount AS deposit_amount, p.payment_status AS deposit_status,
       DATEDIFF(lo.due_date, CURDATE()) AS days_left,
       CASE WHEN lo.returned_at IS NULL THEN lo.due_date < CURDATE()
            ELSE DATE(lo.returned_at) > lo.due_date END AS is_late
FROM loans lo
JOIN transactions t      ON t.transaction_id = lo.transaction_id
JOIN listing_requests r  ON r.request_id     = t.request_id
JOIN listings l          ON l.listing_id     = r.listing_id
JOIN items i             ON i.item_id        = l.item_id
JOIN users b             ON b.user_id        = r.requester_id
JOIN users o             ON o.user_id        = i.owner_id
LEFT JOIN payments p     ON p.transaction_id = lo.transaction_id AND p.payment_type = 'deposit';

CREATE VIEW v_overdue_loans AS
SELECT transaction_id, item_name, borrower_name, borrower_phone, owner_name,
       due_date, DATEDIFF(CURDATE(), due_date) AS days_overdue,
       deposit_amount, deposit_status
FROM v_loan_details
WHERE returned_at IS NULL AND due_date < CURDATE();

CREATE VIEW v_leaderboard AS
SELECT u.user_id, u.name, u.branch,
       COALESCE(SUM(sp.points), 0) AS total_points,
       RANK() OVER (ORDER BY COALESCE(SUM(sp.points), 0) DESC) AS rank_no
FROM users u
LEFT JOIN sustainability_points sp ON sp.user_id = u.user_id
WHERE u.account_role = 'student' AND u.verification_status = 'verified'
GROUP BY u.user_id, u.name, u.branch;

CREATE VIEW v_transaction_history AS
SELECT t.transaction_id, i.item_name, l.listing_type,
       o.name AS giver_name, rq.name AS receiver_name,
       t.agreed_amount, t.transaction_status, t.handover_location,
       t.created_at, t.completed_at
FROM transactions t
JOIN listing_requests r ON r.request_id = t.request_id
JOIN listings l ON l.listing_id = r.listing_id
JOIN items i    ON i.item_id    = l.item_id
JOIN users o    ON o.user_id    = i.owner_id
JOIN users rq   ON rq.user_id   = r.requester_id;

-- Money saved = original price - amount actually paid (sell, donate, exchange only)
CREATE VIEW v_money_saved AS
SELECT t.transaction_id, r.requester_id AS beneficiary_id, i.item_name, l.listing_type,
       i.original_price, t.agreed_amount,
       (i.original_price - t.agreed_amount) AS amount_saved
FROM transactions t
JOIN listing_requests r ON r.request_id = t.request_id
JOIN listings l ON l.listing_id = r.listing_id
JOIN items i    ON i.item_id    = l.item_id
WHERE t.transaction_status = 'completed'
  AND l.listing_type IN ('sale','donation','exchange');

CREATE VIEW v_open_disputes AS
SELECT d.dispute_id, d.transaction_id, i.item_name, d.dispute_reason, d.description,
       d.resolution_status, u.name AS raised_by_name, d.raised_at
FROM disputes d
JOIN users u ON u.user_id = d.raised_by
JOIN transactions t     ON t.transaction_id = d.transaction_id
JOIN listing_requests r ON r.request_id = t.request_id
JOIN listings l ON l.listing_id = r.listing_id
JOIN items i    ON i.item_id    = l.item_id
WHERE d.resolution_status IN ('open','under_review');

CREATE VIEW v_unverified_users AS
SELECT user_id, name, roll_number, university_email, branch, study_year, joined_at
FROM users
WHERE verification_status = 'pending';

-- ===============================================================
-- TRIGGERS  (business rules)
-- ===============================================================
DELIMITER $$

-- Only verified, active students can post a listing; one live listing per item
CREATE TRIGGER trg_listing_before_insert BEFORE INSERT ON listings
FOR EACH ROW
BEGIN
    DECLARE v_ver VARCHAR(10);
    DECLARE v_acc VARCHAR(10);
    SELECT u.verification_status, u.account_status INTO v_ver, v_acc
    FROM items i JOIN users u ON u.user_id = i.owner_id
    WHERE i.item_id = NEW.item_id;
    IF v_ver IS NULL OR v_ver <> 'verified' OR v_acc <> 'active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only verified, active students can post listings';
    END IF;
    IF EXISTS (SELECT 1 FROM listings WHERE item_id = NEW.item_id
               AND listing_status IN ('active','reserved')) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This item already has a live listing';
    END IF;
END$$

-- Only verified students can request; no self-requests; exchange needs an offered item
CREATE TRIGGER trg_request_before_insert BEFORE INSERT ON listing_requests
FOR EACH ROW
BEGIN
    DECLARE v_owner INT;
    DECLARE v_lstatus VARCHAR(10);
    DECLARE v_ltype VARCHAR(10);
    DECLARE v_ver VARCHAR(10);
    DECLARE v_acc VARCHAR(10);
    DECLARE v_off_owner INT;

    SELECT i.owner_id, l.listing_status, l.listing_type INTO v_owner, v_lstatus, v_ltype
    FROM listings l JOIN items i ON i.item_id = l.item_id
    WHERE l.listing_id = NEW.listing_id;

    SELECT verification_status, account_status INTO v_ver, v_acc
    FROM users WHERE user_id = NEW.requester_id;

    IF v_ver IS NULL OR v_ver <> 'verified' OR v_acc <> 'active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only verified, active students can send requests';
    END IF;
    IF v_owner = NEW.requester_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'You cannot request your own listing';
    END IF;
    IF v_lstatus <> 'active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This listing is not open for requests';
    END IF;
    IF v_ltype = 'exchange' THEN
        IF NEW.offered_item_id IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Exchange requests must offer an item';
        END IF;
        SELECT owner_id INTO v_off_owner FROM items WHERE item_id = NEW.offered_item_id;
        IF v_off_owner IS NULL OR v_off_owner <> NEW.requester_id THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'You can only offer an item that you own';
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_request_after_insert AFTER INSERT ON listing_requests
FOR EACH ROW
BEGIN
    DECLARE v_owner INT;
    DECLARE v_item VARCHAR(120);
    SELECT i.owner_id, i.item_name INTO v_owner, v_item
    FROM listings l JOIN items i ON i.item_id = l.item_id
    WHERE l.listing_id = NEW.listing_id;
    INSERT INTO notifications (user_id, notif_type, message)
    VALUES (v_owner, 'request', CONCAT('New request on your listing "', v_item, '"'));
END$$

CREATE TRIGGER trg_request_after_update AFTER UPDATE ON listing_requests
FOR EACH ROW
BEGIN
    DECLARE v_item VARCHAR(120);
    IF OLD.request_status <> NEW.request_status
       AND NEW.request_status IN ('accepted','rejected') THEN
        SELECT i.item_name INTO v_item
        FROM listings l JOIN items i ON i.item_id = l.item_id
        WHERE l.listing_id = NEW.listing_id;
        INSERT INTO notifications (user_id, notif_type, message)
        VALUES (NEW.requester_id, 'request',
                CONCAT('Your request for "', v_item, '" was ', NEW.request_status));
    END IF;
END$$

-- A sale cannot be completed until its payment is marked paid
CREATE TRIGGER trg_txn_before_update BEFORE UPDATE ON transactions
FOR EACH ROW
BEGIN
    IF OLD.transaction_status <> 'completed' AND NEW.transaction_status = 'completed' THEN
        IF EXISTS (SELECT 1 FROM payments
                   WHERE transaction_id = NEW.transaction_id
                     AND payment_type = 'purchase' AND payment_status <> 'completed') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sale payment is not confirmed yet';
        END IF;
    END IF;
END$$

-- On completion: award sustainability points, update listing, notify both students
CREATE TRIGGER trg_txn_after_update AFTER UPDATE ON transactions
FOR EACH ROW
BEGIN
    DECLARE v_listing INT;
    DECLARE v_type VARCHAR(10);
    DECLARE v_owner INT;
    DECLARE v_req INT;
    DECLARE v_item VARCHAR(120);
    DECLARE v_pts INT;
    IF OLD.transaction_status <> 'completed' AND NEW.transaction_status = 'completed' THEN
        SELECT l.listing_id, l.listing_type, i.owner_id, r.requester_id, i.item_name
          INTO v_listing, v_type, v_owner, v_req, v_item
        FROM listing_requests r
        JOIN listings l ON l.listing_id = r.listing_id
        JOIN items i    ON i.item_id    = l.item_id
        WHERE r.request_id = NEW.request_id;

        SET v_pts = CASE v_type WHEN 'donation' THEN 20 WHEN 'lend' THEN 15
                                WHEN 'exchange' THEN 15 ELSE 10 END;

        INSERT INTO sustainability_points (user_id, transaction_id, points, reason)
        VALUES (v_owner, NEW.transaction_id, v_pts, CONCAT('Shared an item (', v_type, ')')),
               (v_req,   NEW.transaction_id, 5,     'Reused an item instead of buying new');

        IF v_type = 'lend' THEN
            UPDATE listings SET listing_status = 'active'    WHERE listing_id = v_listing;
        ELSE
            UPDATE listings SET listing_status = 'completed' WHERE listing_id = v_listing;
        END IF;

        INSERT INTO notifications (user_id, notif_type, message) VALUES
            (v_owner, 'points', CONCAT('You earned ', v_pts, ' sustainability points for "', v_item, '"')),
            (v_req,   'points', CONCAT('You earned 5 sustainability points for reusing "', v_item, '"'));
    END IF;
END$$

-- Return handling: mark returned, settle the deposit, finish the order
CREATE TRIGGER trg_loan_before_update BEFORE UPDATE ON loans
FOR EACH ROW
BEGIN
    IF OLD.returned_at IS NULL AND NEW.returned_at IS NOT NULL THEN
        SET NEW.loan_status = 'returned';
    END IF;
END$$

CREATE TRIGGER trg_loan_after_update AFTER UPDATE ON loans
FOR EACH ROW
BEGIN
    DECLARE v_late INT;
    DECLARE v_owner INT;
    DECLARE v_borrower INT;
    DECLARE v_item VARCHAR(120);
    IF OLD.returned_at IS NULL AND NEW.returned_at IS NOT NULL THEN
        SELECT i.owner_id, r.requester_id, i.item_name INTO v_owner, v_borrower, v_item
        FROM transactions t
        JOIN listing_requests r ON r.request_id = t.request_id
        JOIN listings l ON l.listing_id = r.listing_id
        JOIN items i    ON i.item_id    = l.item_id
        WHERE t.transaction_id = NEW.transaction_id;

        SET v_late = (DATE(NEW.returned_at) > NEW.due_date);

        IF v_late = 0 AND COALESCE(NEW.returned_good_condition, 0) = 1 THEN
            UPDATE payments SET payment_status = 'refunded'
            WHERE transaction_id = NEW.transaction_id
              AND payment_type = 'deposit' AND payment_status = 'completed';
            INSERT INTO notifications (user_id, notif_type, message)
            VALUES (v_borrower, 'deposit',
                    CONCAT('Thanks for returning "', v_item, '" on time. Your deposit is refunded'));
        ELSE
            INSERT INTO notifications (user_id, notif_type, message) VALUES
                (v_borrower, 'deposit',
                 CONCAT('"', v_item, '" was returned late or not in good condition. Your deposit stays held until admin review')),
                (v_owner, 'deposit',
                 CONCAT('"', v_item, '" was returned late or not in good condition. You can raise a dispute'));
        END IF;

        UPDATE transactions SET transaction_status = 'completed', completed_at = NEW.returned_at
        WHERE transaction_id = NEW.transaction_id
          AND transaction_status IN ('pending_handover', 'in_progress');
    END IF;
END$$

-- Reviews: only the two students of a completed order can review each other
CREATE TRIGGER trg_review_before_insert BEFORE INSERT ON reviews
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_owner INT;
    DECLARE v_req INT;
    SELECT t.transaction_status, i.owner_id, r.requester_id INTO v_status, v_owner, v_req
    FROM transactions t
    JOIN listing_requests r ON r.request_id = t.request_id
    JOIN listings l ON l.listing_id = r.listing_id
    JOIN items i    ON i.item_id    = l.item_id
    WHERE t.transaction_id = NEW.transaction_id;
    IF v_status IS NULL OR v_status <> 'completed' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reviews are allowed only after the transaction is completed';
    END IF;
    IF NOT ((NEW.reviewer_id = v_req AND NEW.reviewee_id = v_owner)
         OR (NEW.reviewer_id = v_owner AND NEW.reviewee_id = v_req)) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reviewer and reviewee must be the two students of this transaction';
    END IF;
END$$

CREATE TRIGGER trg_review_after_insert AFTER INSERT ON reviews
FOR EACH ROW
BEGIN
    INSERT INTO notifications (user_id, notif_type, message)
    VALUES (NEW.reviewee_id, 'review', CONCAT('You received a ', NEW.rating, '-star review'));
END$$

-- Disputes: only a student of that transaction can raise one; admins are notified
CREATE TRIGGER trg_dispute_before_insert BEFORE INSERT ON disputes
FOR EACH ROW
BEGIN
    DECLARE v_owner INT;
    DECLARE v_req INT;
    SELECT i.owner_id, r.requester_id INTO v_owner, v_req
    FROM transactions t
    JOIN listing_requests r ON r.request_id = t.request_id
    JOIN listings l ON l.listing_id = r.listing_id
    JOIN items i    ON i.item_id    = l.item_id
    WHERE t.transaction_id = NEW.transaction_id;
    IF v_req IS NULL OR NEW.raised_by NOT IN (v_req, v_owner) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a student of this transaction can raise a dispute';
    END IF;
END$$

CREATE TRIGGER trg_dispute_after_insert AFTER INSERT ON disputes
FOR EACH ROW
BEGIN
    DECLARE v_owner INT;
    DECLARE v_req INT;
    SELECT i.owner_id, r.requester_id INTO v_owner, v_req
    FROM transactions t
    JOIN listing_requests r ON r.request_id = t.request_id
    JOIN listings l ON l.listing_id = r.listing_id
    JOIN items i    ON i.item_id    = l.item_id
    WHERE t.transaction_id = NEW.transaction_id;

    INSERT INTO notifications (user_id, notif_type, message)
    SELECT user_id, 'dispute',
           CONCAT('New dispute #', NEW.dispute_id, ' (', NEW.dispute_reason, ') needs review')
    FROM users WHERE account_role = 'admin';

    INSERT INTO notifications (user_id, notif_type, message)
    VALUES (IF(NEW.raised_by = v_req, v_owner, v_req), 'dispute',
            CONCAT('A dispute (#', NEW.dispute_id, ') was raised on one of your transactions'));
END$$

CREATE TRIGGER trg_dispute_after_update AFTER UPDATE ON disputes
FOR EACH ROW
BEGIN
    DECLARE v_owner INT;
    DECLARE v_req INT;
    IF OLD.resolution_status <> NEW.resolution_status
       AND NEW.resolution_status IN ('resolved','rejected') THEN
        SELECT i.owner_id, r.requester_id INTO v_owner, v_req
        FROM transactions t
        JOIN listing_requests r ON r.request_id = t.request_id
        JOIN listings l ON l.listing_id = r.listing_id
        JOIN items i    ON i.item_id    = l.item_id
        WHERE t.transaction_id = NEW.transaction_id;
        INSERT INTO notifications (user_id, notif_type, message) VALUES
            (v_owner, 'dispute', CONCAT('Dispute #', NEW.dispute_id, ' was ', NEW.resolution_status)),
            (v_req,   'dispute', CONCAT('Dispute #', NEW.dispute_id, ' was ', NEW.resolution_status));
    END IF;
END$$

-- Tell the student when admin verifies or rejects the account
CREATE TRIGGER trg_user_after_update AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    IF OLD.verification_status <> NEW.verification_status
       AND NEW.verification_status IN ('verified','rejected') THEN
        INSERT INTO notifications (user_id, notif_type, message)
        VALUES (NEW.user_id, 'account', CONCAT('Your account was ', NEW.verification_status, ' by admin'));
    END IF;
END$$

-- ===============================================================
-- STORED PROCEDURES  (the "actions" of the system)
-- ===============================================================

-- Owner accepts a request: creates the order, saves handover details,
-- rejects other pending requests, creates loan / payment rows as needed
CREATE PROCEDURE accept_request(IN p_request INT, IN p_location VARCHAR(120), IN p_time DATETIME)
BEGIN
    DECLARE v_listing INT;
    DECLARE v_req_status VARCHAR(10);
    DECLARE v_requester INT;
    DECLARE v_type VARCHAR(10);
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_deposit DECIMAL(10,2);
    DECLARE v_days INT;
    DECLARE v_lstatus VARCHAR(10);
    DECLARE v_txn INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT r.listing_id, r.request_status, r.requester_id, l.listing_type,
           l.price, l.deposit_amount, l.max_loan_days, l.listing_status
      INTO v_listing, v_req_status, v_requester, v_type,
           v_price, v_deposit, v_days, v_lstatus
    FROM listing_requests r JOIN listings l ON l.listing_id = r.listing_id
    WHERE r.request_id = p_request;

    IF v_listing IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Request not found';
    END IF;
    IF v_req_status <> 'pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only pending requests can be accepted';
    END IF;
    IF v_lstatus <> 'active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Listing is no longer active';
    END IF;

    START TRANSACTION;
    UPDATE listing_requests SET request_status = 'accepted' WHERE request_id = p_request;
    UPDATE listing_requests SET request_status = 'rejected'
        WHERE listing_id = v_listing AND request_id <> p_request AND request_status = 'pending';
    UPDATE listings SET listing_status = 'reserved' WHERE listing_id = v_listing;

    INSERT INTO transactions (request_id, agreed_amount, handover_location, handover_time)
    VALUES (p_request, v_price, p_location, p_time);
    SET v_txn = LAST_INSERT_ID();

    IF v_type = 'sale' AND v_price > 0 THEN
        INSERT INTO payments (transaction_id, payer_id, payment_type, amount, payment_status)
        VALUES (v_txn, v_requester, 'purchase', v_price, 'pending');
    END IF;

    IF v_type = 'lend' THEN
        INSERT INTO loans (transaction_id, due_date)
        VALUES (v_txn, DATE_ADD(CURDATE(), INTERVAL v_days DAY));
        IF v_deposit > 0 THEN
            INSERT INTO payments (transaction_id, payer_id, payment_type, amount, payment_status, paid_at)
            VALUES (v_txn, v_requester, 'deposit', v_deposit, 'completed', NOW());
        END IF;
    END IF;
    COMMIT;
END$$

CREATE PROCEDURE reject_request(IN p_request INT)
BEGIN
    UPDATE listing_requests SET request_status = 'rejected'
    WHERE request_id = p_request AND request_status = 'pending';
END$$

CREATE PROCEDURE confirm_payment(IN p_txn INT, IN p_method VARCHAR(10))
BEGIN
    UPDATE payments
    SET payment_status = 'completed', payment_method = p_method, paid_at = NOW()
    WHERE transaction_id = p_txn AND payment_type = 'purchase' AND payment_status = 'pending';
END$$

-- For sell / donate / exchange orders (lend orders finish through return_item)
CREATE PROCEDURE complete_transaction(IN p_txn INT)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_type VARCHAR(10);
    SELECT t.transaction_status, l.listing_type INTO v_status, v_type
    FROM transactions t
    JOIN listing_requests r ON r.request_id = t.request_id
    JOIN listings l ON l.listing_id = r.listing_id
    WHERE t.transaction_id = p_txn;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transaction not found';
    END IF;
    IF v_status NOT IN ('pending_handover','in_progress') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transaction is not ready for completion';
    END IF;
    IF v_type = 'lend' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lend orders are completed when the item is returned';
    END IF;
    UPDATE transactions SET transaction_status = 'completed', completed_at = NOW()
    WHERE transaction_id = p_txn;
END$$

CREATE PROCEDURE return_item(IN p_txn INT, IN p_good BOOLEAN, IN p_note TEXT, IN p_returned_at DATETIME)
BEGIN
    DECLARE v_open INT;
    SELECT COUNT(*) INTO v_open FROM loans
    WHERE transaction_id = p_txn AND returned_at IS NULL;
    IF v_open = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No open loan found for this transaction';
    END IF;
    UPDATE loans
    SET returned_at = COALESCE(p_returned_at, NOW()),
        returned_good_condition = p_good,
        condition_on_return = p_note
    WHERE transaction_id = p_txn AND returned_at IS NULL;
END$$

CREATE PROCEDURE resolve_dispute(IN p_dispute INT, IN p_admin INT, IN p_status VARCHAR(10),
                                 IN p_resolution TEXT, IN p_deduct BOOLEAN)
BEGIN
    DECLARE v_role VARCHAR(10);
    DECLARE v_txn INT;
    DECLARE v_cur VARCHAR(15);
    SELECT account_role INTO v_role FROM users WHERE user_id = p_admin;
    IF v_role IS NULL OR v_role <> 'admin' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only an admin can resolve disputes';
    END IF;
    IF p_status NOT IN ('resolved','rejected') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Status must be resolved or rejected';
    END IF;
    SELECT transaction_id, resolution_status INTO v_txn, v_cur
    FROM disputes WHERE dispute_id = p_dispute;
    IF v_txn IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Dispute not found';
    END IF;
    IF v_cur IN ('resolved','rejected') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Dispute is already closed';
    END IF;

    UPDATE disputes
    SET resolution_status = p_status, resolution = p_resolution,
        assigned_admin = p_admin, resolved_at = NOW()
    WHERE dispute_id = p_dispute;

    -- any deposit still held is either deducted (owner wins) or given back
    UPDATE payments
    SET payment_status = IF(p_deduct AND p_status = 'resolved', 'completed', 'refunded')
    WHERE transaction_id = v_txn AND payment_type = 'deposit' AND payment_status = 'completed';
END$$

CREATE PROCEDURE verify_user(IN p_user INT, IN p_admin INT, IN p_status VARCHAR(10))
BEGIN
    DECLARE v_role VARCHAR(10);
    SELECT account_role INTO v_role FROM users WHERE user_id = p_admin;
    IF v_role IS NULL OR v_role <> 'admin' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only an admin can verify accounts';
    END IF;
    UPDATE users SET verification_status = p_status WHERE user_id = p_user;
END$$

-- Run daily (or from Python): due-tomorrow reminders and overdue marking
CREATE PROCEDURE refresh_overdue()
BEGIN
    INSERT INTO notifications (user_id, notif_type, message)
    SELECT lo.borrower_id, 'reminder',
           CONCAT('Reminder: "', lo.item_name, '" is due back tomorrow (', lo.due_date, ')')
    FROM v_loan_details lo
    JOIN loans l2 ON l2.transaction_id = lo.transaction_id
    WHERE lo.returned_at IS NULL AND l2.reminder_sent = FALSE
      AND lo.due_date = DATE_ADD(CURDATE(), INTERVAL 1 DAY);
    UPDATE loans SET reminder_sent = TRUE
    WHERE returned_at IS NULL AND reminder_sent = FALSE
      AND due_date = DATE_ADD(CURDATE(), INTERVAL 1 DAY);

    INSERT INTO notifications (user_id, notif_type, message)
    SELECT borrower_id, 'overdue',
           CONCAT('Overdue: please return "', item_name, '" (was due ', due_date, ')')
    FROM v_loan_details
    WHERE returned_at IS NULL AND loan_status = 'active' AND due_date < CURDATE();
    INSERT INTO notifications (user_id, notif_type, message)
    SELECT owner_id, 'overdue',
           CONCAT(borrower_name, ' has not returned "', item_name, '" (due ', due_date, ')')
    FROM v_loan_details
    WHERE returned_at IS NULL AND loan_status = 'active' AND due_date < CURDATE();

END$$

DELIMITER ;
