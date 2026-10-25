CREATE DATABASE IF NOT EXISTS aers;
USE aers;

CREATE TABLE users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(120) NOT NULL UNIQUE,
  phone VARCHAR(20),
  password_hash VARCHAR(255) NOT NULL,
  blood_group VARCHAR(5),
  role ENUM('user','admin') DEFAULT 'user',
  fcm_token VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE emergency_contacts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  name VARCHAR(100) NOT NULL,
  phone VARCHAR(20) NOT NULL,
  relation VARCHAR(30),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE hospitals (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  phone VARCHAR(20),
  city VARCHAR(60),
  lat DOUBLE NOT NULL,
  lng DOUBLE NOT NULL
);

CREATE TABLE police_stations (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  phone VARCHAR(20),
  city VARCHAR(60),
  lat DOUBLE NOT NULL,
  lng DOUBLE NOT NULL
);

CREATE TABLE ambulances (
  id INT AUTO_INCREMENT PRIMARY KEY,
  vehicle_no VARCHAR(20) NOT NULL,
  driver_name VARCHAR(80),
  phone VARCHAR(20),
  lat DOUBLE,
  lng DOUBLE,
  status ENUM('available','on_route','busy') DEFAULT 'available'
);

CREATE TABLE accidents (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  source ENUM('sos','report','auto') DEFAULT 'report',
  accident_type VARCHAR(30),
  vehicle_no VARCHAR(20),
  people_count INT DEFAULT 1,
  description TEXT,
  lat DOUBLE NOT NULL,
  lng DOUBLE NOT NULL,
  severity ENUM('Minor','Moderate','Severe') NULL,
  confidence FLOAT NULL,
  status ENUM('pending','in_progress','resolved') DEFAULT 'pending',
  hospital_id INT NULL,
  police_id INT NULL,
  ambulance_id INT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (hospital_id) REFERENCES hospitals(id),
  FOREIGN KEY (police_id) REFERENCES police_stations(id),
  FOREIGN KEY (ambulance_id) REFERENCES ambulances(id)
);

CREATE TABLE notifications (
  id INT AUTO_INCREMENT PRIMARY KEY,
  accident_id INT NOT NULL,
  target_type ENUM('hospital','police','family') NOT NULL,
  target_id INT NOT NULL,
  status ENUM('sent','acknowledged') DEFAULT 'sent',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (accident_id) REFERENCES accidents(id) ON DELETE CASCADE
);

CREATE TABLE donors (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  phone VARCHAR(20),
  blood_group VARCHAR(5) NOT NULL,
  city VARCHAR(60),
  lat DOUBLE,
  lng DOUBLE
);