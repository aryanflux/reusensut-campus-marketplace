-- ReUseNSUT : Verified Campus Sharing Marketplace
-- File 1 of 4 : database + tables   (MySQL 8.0.16 or newer)

USE reusensut;

-- Module 1 : User and Verification (+ Module 11 Admin via role)
CREATE TABLE users (
    user_id             INT AUTO_INCREMENT PRIMARY KEY,
    roll_number         VARCHAR(30)  NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    university_email    VARCHAR(150) NOT NULL UNIQUE,
    phone               VARCHAR(20)  NULL UNIQUE,
    password_hash       VARCHAR(255) NOT NULL,
    branch              VARCHAR(50)  NOT NULL,
    study_year          TINYINT      NOT NULL,
    residence           ENUM('hostel','day_scholar') NOT NULL DEFAULT 'hostel',
    verification_status ENUM('pending','verified','rejected') NOT NULL DEFAULT 'pending',
    account_role        ENUM('student','admin') NOT NULL DEFAULT 'student',
    account_status      ENUM('active','suspended','deactivated') NOT NULL DEFAULT 'active',
    joined_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_nsut_email CHECK (university_email LIKE '%@nsut.ac.in'),
    CONSTRAINT chk_roll_format CHECK (roll_number REGEXP '^[0-9]{4}[A-Z]{3}[0-9]{4}$'),
    CONSTRAINT chk_study_year CHECK (study_year BETWEEN 1 AND 4)
);

-- Module 2 : Item and Category
CREATE TABLE categories (
    category_id   INT AUTO_INCREMENT PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    description   TEXT
);

CREATE TABLE items (
    item_id        INT AUTO_INCREMENT PRIMARY KEY,
    owner_id       INT NOT NULL,
    category_id    INT NOT NULL,
    item_name      VARCHAR(150) NOT NULL,
    description    TEXT,
    item_condition ENUM('new','like_new','good','fair','poor') NOT NULL DEFAULT 'good',
    semester       TINYINT NULL,                         -- for textbooks (1-8)
    original_price DECIMAL(10,2) NOT NULL DEFAULT 0,     -- used for "money saved"
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (owner_id)    REFERENCES users(user_id),
    FOREIGN KEY (category_id) REFERENCES categories(category_id),
    CONSTRAINT chk_semester CHECK (semester IS NULL OR semester BETWEEN 1 AND 8),
    CONSTRAINT chk_orig_price CHECK (original_price >= 0)
);

CREATE TABLE item_images (
    image_id    INT AUTO_INCREMENT PRIMARY KEY,
    item_id     INT NOT NULL,
    image_url   VARCHAR(500) NOT NULL,
    uploaded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (item_id) REFERENCES items(item_id) ON DELETE CASCADE
);


-- Module 3 : Listing  (sale / lend / exchange / donation)
CREATE TABLE listings (
    listing_id     INT AUTO_INCREMENT PRIMARY KEY,
    item_id        INT NOT NULL,
    listing_type   ENUM('sale','lend','exchange','donation') NOT NULL,
    price          DECIMAL(10,2) NOT NULL DEFAULT 0,
    deposit_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    max_loan_days  SMALLINT NULL,                        -- only for lend
    posted_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expiry_date    DATE NULL,
    listing_status ENUM('active','reserved','completed','withdrawn','expired') NOT NULL DEFAULT 'active',
    FOREIGN KEY (item_id) REFERENCES items(item_id),
    CONSTRAINT chk_price CHECK (price >= 0),
    CONSTRAINT chk_deposit CHECK (deposit_amount >= 0),
    CONSTRAINT chk_deposit_only_lend CHECK (listing_type = 'lend' OR deposit_amount = 0),
    CONSTRAINT chk_lend_days CHECK (listing_type <> 'lend' OR (max_loan_days IS NOT NULL AND max_loan_days > 0)),
    CONSTRAINT     chk_donation_free CHECK (listing_type <> 'donation' OR price = 0)
);

CREATE TABLE saved_listings (
    user_id    INT NOT NULL,
    listing_id INT NOT NULL,
    saved_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, listing_id),
    FOREIGN KEY (user_id)    REFERENCES users(user_id)       ON DELETE CASCADE,
    FOREIGN KEY (listing_id) REFERENCES listings(listing_id) ON DELETE CASCADE
);

CREATE TABLE messages (
    message_id   INT AUTO_INCREMENT PRIMARY KEY,
    sender_id    INT NOT NULL,
    receiver_id  INT NOT NULL,
    listing_id   INT NULL,
    message_text TEXT NOT NULL,
    sent_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    read_at      TIMESTAMP NULL,
    FOREIGN KEY (sender_id)   REFERENCES users(user_id),
    FOREIGN KEY (receiver_id) REFERENCES users(user_id),
    FOREIGN KEY (listing_id)  REFERENCES listings(listing_id),
    CONSTRAINT chk_msg_parties CHECK (sender_id <> receiver_id)
);

-- Module 4 : Request and Order
CREATE TABLE listing_requests (
    request_id      INT AUTO_INCREMENT PRIMARY KEY,
    listing_id      INT NOT NULL,
    requester_id    INT NOT NULL,
    offered_item_id INT NULL,                            -- only for exchange
    request_message TEXT,
    requested_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    request_status  ENUM('pending','accepted','rejected','cancelled','fulfilled') NOT NULL DEFAULT 'pending',
    UNIQUE KEY uq_one_request (listing_id, requester_id),
    FOREIGN KEY (listing_id)      REFERENCES listings(listing_id),
    FOREIGN KEY (requester_id)    REFERENCES users(user_id),
    FOREIGN KEY (offered_item_id) REFERENCES items(item_id)
);

CREATE TABLE transactions (
    transaction_id     INT AUTO_INCREMENT PRIMARY KEY,
    request_id         INT NOT NULL UNIQUE,              -- 1 accepted request = 1 order
    transaction_status ENUM('pending_handover','in_progress','completed','cancelled','disputed') NOT NULL DEFAULT 'pending_handover',
    agreed_amount      DECIMAL(10,2) NOT NULL DEFAULT 0,
    handover_location  VARCHAR(120),
    handover_time      DATETIME,
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at       TIMESTAMP NULL,
    FOREIGN KEY (request_id) REFERENCES listing_requests(request_id)
);

-- Module 5 : Loan and Return
CREATE TABLE loans (
    transaction_id          INT PRIMARY KEY,
    borrowed_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    due_date                DATE NOT NULL,
    returned_at             TIMESTAMP NULL,
    loan_status             ENUM('active','returned','lost') NOT NULL DEFAULT 'active',
    returned_good_condition BOOLEAN NULL,
    condition_on_return     TEXT,
    reminder_sent           BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id)
);

-- Module 6 : Payment and Deposit
CREATE TABLE payments (
    payment_id     INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id INT NOT NULL,
    payer_id       INT NOT NULL,
    payment_type   ENUM('purchase','deposit','refund','penalty') NOT NULL,
    amount         DECIMAL(10,2) NOT NULL,
    payment_method ENUM('upi','cash','other') NOT NULL DEFAULT 'cash',
    payment_status ENUM('pending','completed','failed','refunded') NOT NULL DEFAULT 'pending',
    paid_at        TIMESTAMP NULL,
    UNIQUE KEY uq_payment_kind (transaction_id, payment_type),
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id),
    FOREIGN KEY (payer_id)       REFERENCES users(user_id),
    CONSTRAINT chk_amount CHECK (amount >= 0)
);

-- Module 7 : Review and Trust Score (trust score = view, see 02 file)
CREATE TABLE reviews (
    review_id      INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id INT NOT NULL,
    reviewer_id    INT NOT NULL,
    reviewee_id    INT NOT NULL,
    rating         TINYINT NOT NULL,
    comment        TEXT,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_one_review (transaction_id, reviewer_id),
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id),
    FOREIGN KEY (reviewer_id)    REFERENCES users(user_id),
    FOREIGN KEY (reviewee_id)    REFERENCES users(user_id),
    CONSTRAINT chk_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT chk_review_parties CHECK (reviewer_id <> reviewee_id)
);

-- Module 8 : Dispute  (+ reports and admin actions)
CREATE TABLE disputes (
    dispute_id        INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id    INT NOT NULL,
    raised_by         INT NOT NULL,
    dispute_reason    ENUM('item_damaged','item_not_returned','not_as_described','payment_issue','other') NOT NULL,
    description       TEXT NOT NULL,
    resolution_status ENUM('open','under_review','resolved','rejected') NOT NULL DEFAULT 'open',
    resolution        TEXT,
    assigned_admin    INT NULL,
    raised_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at       TIMESTAMP NULL,
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id),
    FOREIGN KEY (raised_by)      REFERENCES users(user_id),
    FOREIGN KEY (assigned_admin) REFERENCES users(user_id)
);

CREATE TABLE reports (
    report_id        INT AUTO_INCREMENT PRIMARY KEY,
    reporter_id      INT NOT NULL,
    reported_user_id INT NULL,
    listing_id       INT NULL,
    report_reason    VARCHAR(120) NOT NULL,
    description      TEXT,
    report_status     ENUM('pending','under_review','action_taken','dismissed') NOT NULL DEFAULT 'pending',
    reported_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reporter_id)      REFERENCES users(user_id),
    FOREIGN KEY (reported_user_id) REFERENCES users(user_id),
    FOREIGN KEY (listing_id)       REFERENCES listings(listing_id),
    CONSTRAINT chk_report_parties CHECK (reported_user_id IS NULL OR reporter_id <> reported_user_id)
);

CREATE TABLE report_actions (
    report_action_id INT AUTO_INCREMENT PRIMARY KEY,
    report_id        INT NOT NULL,
    admin_id         INT NOT NULL,
    action_taken     VARCHAR(120) NOT NULL,
    action_details   TEXT,
    action_date      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (report_id) REFERENCES reports(report_id),
    FOREIGN KEY (admin_id)  REFERENCES users(user_id)
);

-- Module 9 : Notification
CREATE TABLE notifications (
    notification_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id         INT NOT NULL,
    notif_type      VARCHAR(30) NOT NULL,
    message         VARCHAR(300) NOT NULL,
    is_read         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- Module 10 : Sustainability Points
CREATE TABLE sustainability_points (
    point_id       INT AUTO_INCREMENT PRIMARY KEY,
    user_id        INT NOT NULL,
    transaction_id INT NOT NULL,
    points         INT NOT NULL,
    reason         VARCHAR(100) NOT NULL,
    awarded_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id)        REFERENCES users(user_id),
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id),
    CONSTRAINT chk_points CHECK (points > 0)
);

-- Helpful indexes for the demo queries
CREATE INDEX idx_listings_status_type ON listings(listing_status, listing_type);
CREATE INDEX idx_items_category_sem   ON items(category_id, semester);
CREATE INDEX idx_notif_user           ON notifications(user_id, is_read);
CREATE INDEX idx_loans_due            ON loans(due_date, returned_at);
