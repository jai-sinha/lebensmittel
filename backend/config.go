package main

import (
	"os"
	"strconv"
)

// Config holds all configuration for the application
type Config struct {
	DatabaseURL string
	Port        string
	SecretKey   string
	Debug       bool
}

// LoadConfig loads configuration from environment variables
func LoadConfig() *Config {
	config := &Config{
		DatabaseURL: getEnv("DATABASE_URL", "postgres://jsinha:@localhost/lebensmittel"),
		Port:        getEnv("PORT", "8000"),
		SecretKey:   getEnv("SECRET_KEY", "your-secret-key-here"),
		Debug:       getEnvBool("DEBUG", false),
	}

	return config
}

// getEnv gets an environment variable with a default fallback
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvBool gets a boolean environment variable with a default fallback
func getEnvBool(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		if parsed, err := strconv.ParseBool(value); err == nil {
			return parsed
		}
	}
	return defaultValue
}
