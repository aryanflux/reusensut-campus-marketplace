-- ReUseNSUT : File 3 of 4 : synthetic demo data (no real student records)
-- Dates are relative to CURDATE() so the overdue / reminder demos always work.
USE reusensut;

-- ---------------- users (password for everyone: Reuse@123) -----------------
INSERT INTO users (roll_number, name, university_email, phone, password_hash, branch, study_year, residence, verification_status, account_role) VALUES
('2020UZZ0001','Demo Admin',  'demo.admin01@nsut.ac.in',  '0000000001', SHA2('Reuse@123',256), 'Admin', 4, 'day_scholar', 'verified', 'admin'),
('2025UCS0002','Student 02',  'demo.student02@nsut.ac.in','0000000002', SHA2('Reuse@123',256), 'CSE',   2, 'hostel',      'verified', 'student'),
('2024UCS0003','Student 03',  'demo.student03@nsut.ac.in','0000000003', SHA2('Reuse@123',256), 'CSE',   3, 'day_scholar', 'verified', 'student'),
('2023UEC0004','Student 04',  'demo.student04@nsut.ac.in','0000000004', SHA2('Reuse@123',256), 'ECE',   4, 'hostel',      'verified', 'student'),
('2024UIT0005','Student 05',  'demo.student05@nsut.ac.in','0000000005', SHA2('Reuse@123',256), 'IT',    3, 'hostel',      'verified', 'student'),
('2023UCS0006','Student 06',  'demo.student06@nsut.ac.in','0000000006', SHA2('Reuse@123',256), 'CSE',   4, 'day_scholar', 'verified', 'student'),
('2024UEE0007','Student 07',  'demo.student07@nsut.ac.in','0000000007', SHA2('Reuse@123',256), 'EE',    3, 'hostel',      'verified', 'student'),
('2026UME0008','Student 08',  'demo.student08@nsut.ac.in','0000000008', SHA2('Reuse@123',256), 'ME',    1, 'hostel',      'verified', 'student'),
('2022UCS0009','Student 09',  'demo.student09@nsut.ac.in','0000000009', SHA2('Reuse@123',256), 'CSE',   4, 'day_scholar', 'verified', 'student'),
('2026UCS0010','Student 10',  'demo.student10@nsut.ac.in','0000000010', SHA2('Reuse@123',256), 'CSE',   1, 'hostel',      'verified', 'student'),
('2026UIT0011','Student 11',  'demo.student11@nsut.ac.in','0000000011', SHA2('Reuse@123',256), 'IT',    1, 'hostel',      'pending',  'student'),
('2025UCS0012','Student 12',  'demo.student12@nsut.ac.in','0000000012', SHA2('Reuse@123',256), 'CSE',   2, 'day_scholar', 'pending',  'student');

-- ---------------- categories -----------------
INSERT INTO categories (category_name, description) VALUES
('Textbooks',      'Semester textbooks and reference books'),
('Calculators',    'Scientific calculators'),
('Lab Equipment',  'Multimeters, breadboards and other lab tools'),
('Drafting Tools', 'Mini drafters, drawing sets and sheets holders'),
('Accessories',    'Lab coats, cooling pads and other accessories'),
('Electronics',    'Development boards and kits');

-- ---------------- items -----------------
INSERT INTO items (owner_id, category_id, item_name, description, item_condition, semester, original_price) VALUES
(3, 1, 'Engineering Mathematics II',        'Clean copy, few pencil marks',            'good',     2, 650),
(6, 1, 'Data Structures Using C',           'Almost new, solved exercises included',   'like_new', 3, 550),
(4, 1, 'Digital Logic Design',              'Highlighted chapters 1 to 5',             'good',     3, 480),
(9, 1, 'Discrete Mathematics',              'Cover is a little worn',                  'fair',     3, 500),
(5, 1, 'Probability and Statistics',        'No writing inside',                       'good',     3, 450),
(3, 2, 'Casio fx-991EX Scientific Calculator','Works perfectly, cover included',       'good',  NULL, 1100),
(9, 2, 'Casio fx-82MS Scientific Calculator','Some scratches on the body',             'fair',  NULL,  700),
(7, 4, 'Mini Drafter',                      'Smooth sliding, no cracks',               'good',     1, 450),
(5, 4, 'Engineering Drawing Set',           'Compass and set squares, barely used',    'like_new', 1, 350),
(4, 6, 'Arduino Uno Starter Kit',           'Board, cables and 10 sensors',            'good',  NULL, 1800),
(7, 3, 'Digital Multimeter',                'Probes and a new battery',                'good',  NULL,  900),
(6, 3, 'Breadboard and Jumper Wire Set',    'Full size breadboard',                    'like_new', NULL, 300),
(6, 5, 'Lab Coat (Size M)',                 'Washed and ironed',                       'good',  NULL,  400),
(2, 1, 'Operating Systems Concepts',        'Like new, no highlights',                 'like_new', 4, 700),
(9, 5, 'Laptop Cooling Pad',                'Both fans work',                          'fair',  NULL,  900),
(7, 1, 'Computer Networks',                 'Good condition, spine intact',            'good',     4, 600);

INSERT INTO item_images (item_id, image_url) VALUES
(1,'https://example.com/img/eng-math-2.jpg'),
(6,'https://example.com/img/casio-991ex.jpg'),
(10,'https://example.com/img/arduino-kit.jpg'),
(11,'https://example.com/img/multimeter.jpg');

-- ---------------- listings -----------------
INSERT INTO listings (item_id, listing_type, price, deposit_amount, max_loan_days, expiry_date) VALUES
(1,  'donation',   0,   0, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
(2,  'sale',   300,   0, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
(3,  'sale',   250,   0, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
(4,  'sale',   200,   0, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
(5,  'lend',     0, 150,   30, DATE_ADD(CURDATE(), INTERVAL 60 DAY)),
(6,  'lend',     0, 400,   14, DATE_ADD(CURDATE(), INTERVAL 60 DAY)),
(7,  'sale',   350,   0, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
(8,  'lend',     0, 200,   60, DATE_ADD(CURDATE(), INTERVAL 60 DAY)),
(9,  'donation',   0,   0, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
(10, 'lend',     0, 500,   21, DATE_ADD(CURDATE(), INTERVAL 60 DAY)),
(11, 'sale',   450,   0, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
(12, 'sale',   120,   0, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
(13, 'donation',   0,   0, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
(14, 'exchange', 0,   0, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
(15, 'sale',   300,   0, NULL, DATE_ADD(CURDATE(), INTERVAL 30 DAY));

INSERT INTO saved_listings (user_id, listing_id) VALUES (2,3), (8,4), (10,7), (10,13);

-- ---------------- requests (ids 1 to 11) -----------------
INSERT INTO listing_requests (listing_id, requester_id, offered_item_id, request_message) VALUES
(1,  10, NULL, 'I am a first year student, this book would help a lot'),
(2,   2, NULL, 'Can I buy this tomorrow near the library'),
(3,   8, NULL, 'Is the book still available'),
(3,  10, NULL, 'I can pay in cash right now'),
(5,   2, NULL, 'Need it for the semester only'),
(6,   8, NULL, 'Need a calculator for my exams'),
(8,  10, NULL, 'Need the drafter for the first year drawing course'),
(9,   2, NULL, 'My juniors can also use it after me'),
(10,  6, NULL, 'For my embedded systems project'),
(14,  7,   16, 'Would you like to swap with my Computer Networks book'),
(11,  8, NULL, 'Can you give it for 300');

INSERT INTO messages (sender_id, receiver_id, listing_id, message_text) VALUES
(8, 4, 3, 'Is the book still available'),
(4, 8, 3, 'Yes, we can meet near the library gate');

-- owner turns down one request
CALL reject_request(11);

-- ---------------- orders (transaction ids 1 to 6) -----------------
CALL accept_request(1,  'Main Library Gate',  DATE_ADD(NOW(), INTERVAL 1 DAY));
CALL accept_request(2,  'Canteen',            DATE_ADD(NOW(), INTERVAL 1 DAY));
CALL accept_request(5,  'Library Reading Hall', DATE_ADD(NOW(), INTERVAL 1 DAY));
CALL accept_request(6,  'Hostel Gate',        DATE_ADD(NOW(), INTERVAL 1 DAY));
CALL accept_request(7,  'Main Library Gate',  DATE_ADD(NOW(), INTERVAL 1 DAY));
CALL accept_request(9,  'Canteen',            DATE_ADD(NOW(), INTERVAL 1 DAY));

-- donation done, sale paid then done
CALL complete_transaction(1);
CALL confirm_payment(2, 'upi');
CALL complete_transaction(2);

-- loan 3 : returned on time, good condition -> deposit refunded
CALL return_item(3, TRUE, 'Returned in perfect condition', NULL);

-- loan 4 : borrower is late (due 5 days ago, still not returned)
UPDATE loans SET borrowed_at = DATE_SUB(NOW(), INTERVAL 19 DAY),
                 due_date    = DATE_SUB(CURDATE(), INTERVAL 5 DAY)
WHERE transaction_id = 4;

-- loan 5 : due tomorrow (reminder demo)
UPDATE loans SET borrowed_at = DATE_SUB(NOW(), INTERVAL 59 DAY),
                 due_date    = DATE_ADD(CURDATE(), INTERVAL 1 DAY)
WHERE transaction_id = 5;

-- loan 6 : returned 3 days late with damage -> deposit stays held
UPDATE loans SET borrowed_at = DATE_SUB(NOW(), INTERVAL 24 DAY),
                 due_date    = DATE_SUB(CURDATE(), INTERVAL 3 DAY)
WHERE transaction_id = 6;
CALL return_item(6, FALSE, 'Returned 3 days late and one header pin is bent', NULL);

-- ---------------- reviews -----------------
INSERT INTO reviews (transaction_id, reviewer_id, reviewee_id, rating, comment) VALUES
(1, 10, 3, 5, 'Book was in great shape. Thank you'),
(1,  3, 10, 5, 'Polite and on time for the handover'),
(2,  2, 6, 4, 'Good book and quick handover'),
(2,  6, 2, 5, 'Smooth payment, recommended'),
(3,  2, 5, 5, 'Very helpful lender'),
(3,  5, 2, 5, 'Returned on time and in perfect condition'),
(6,  4, 6, 2, 'Returned late and a pin was bent'),
(6,  6, 4, 4, 'Kit was complete but instructions were missing');

-- ---------------- disputes -----------------
INSERT INTO disputes (transaction_id, raised_by, dispute_reason, description) VALUES
(2, 2, 'not_as_described', 'I think two pages were missing from chapter 4'),
(6, 4, 'item_damaged',     'Arduino kit came back with a bent header pin and 3 days late');

CALL resolve_dispute(1, 1, 'rejected', 'Photos taken at handover show all pages were present. No action needed.', FALSE);

-- ---------------- report + admin action -----------------
INSERT INTO reports (reporter_id, reported_user_id, listing_id, report_reason, description) VALUES
(4, 6, 10, 'Late return and damage', 'Returned the Arduino kit late and damaged');
INSERT INTO report_actions (report_id, admin_id, action_taken, action_details) VALUES
(1, 1, 'Warning issued', 'Student warned. Deposit decision is pending in dispute 2');
UPDATE reports SET report_status = 'action_taken' WHERE report_id = 1;

-- send reminders and mark overdue loans
CALL refresh_overdue();
