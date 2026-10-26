-- ReUseNSUT : File 4 of 4 : demo queries (the same ones main.py runs)
USE reusensut;

-- 1. BUYER : available 3rd semester textbooks at or under Rs 300, with owner trust score
SELECT listing_id, item_name, listing_type, price, item_condition, owner_name, owner_trust_score
FROM v_available_listings
WHERE category_name = 'Textbooks' AND semester = 3 AND price <= 300
ORDER BY price;

-- 2. LENDER / ADMIN : items overdue today with borrower name
SELECT * FROM v_overdue_loans ORDER BY days_overdue DESC;

-- 3. Top 5 students by sustainability points
SELECT rank_no, name, branch, total_points FROM v_leaderboard ORDER BY rank_no, name LIMIT 5;

-- 4. Students with the highest trust score
SELECT name, avg_rating, review_count, on_time_returns, late_returns, trust_score
FROM v_trust_scores ORDER BY trust_score DESC, name LIMIT 5;

-- 5. Total money saved by students through reuse
SELECT COUNT(*) AS items_reused, SUM(original_price) AS retail_value,
       SUM(agreed_amount) AS actually_paid, SUM(amount_saved) AS total_saved
FROM v_money_saved;

-- 6. SELLER : requests received on my listings (owner_id = 3)
SELECT request_id, item_name, requester_name, requester_trust_score, request_status
FROM v_listing_requests WHERE owner_id = 3;

-- 7. BORROWER : my borrowed items (borrower_id = 8)
SELECT item_name, owner_name, due_date, days_left, deposit_amount, deposit_status, loan_status
FROM v_loan_details WHERE borrower_id = 8 AND returned_at IS NULL;

-- 8. LENDER : my items on loan, not yet returned (owner_id = 7)
SELECT item_name, borrower_name, due_date, days_left, is_late
FROM v_loan_details WHERE owner_id = 7 AND returned_at IS NULL;

-- 9. ADMIN : open disputes and unverified accounts
SELECT * FROM v_open_disputes;
SELECT * FROM v_unverified_users;

-- 10. Any student : my notifications (user_id = 8)
SELECT notif_type, message, created_at FROM notifications WHERE user_id = 8 ORDER BY created_at DESC;
