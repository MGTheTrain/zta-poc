package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"
)

type Response struct {
	Service   string    `json:"service"`
	Message   string    `json:"message"`
	Timestamp time.Time `json:"timestamp"`
	User      string    `json:"user,omitempty"`
}

func main() {
	serviceName := getEnv("SERVICE_NAME", "go-service")
	servicePort := getEnv("SERVICE_PORT", "8080")

	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/health", handleHealth)
	http.HandleFunc("/api/data", handleAPIData)
	http.HandleFunc("/admin/users", handleAdminUsers)

	addr := ":" + servicePort
	log.Printf("%s starting on %s", serviceName, addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	respond(w, Response{
		Service:   getEnv("SERVICE_NAME", "go-service"),
		Message:   "Hello from Go service! This is a public endpoint.",
		Timestamp: time.Now(),
		User:      getUser(r),
	})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	respond(w, map[string]string{"status": "healthy"})
}

func handleAPIData(w http.ResponseWriter, r *http.Request) {
	respond(w, Response{
		Service:   getEnv("SERVICE_NAME", "go-service"),
		Message:   "API data endpoint - requires user or admin role",
		Timestamp: time.Now(),
		User:      getUser(r),
	})
}

func handleAdminUsers(w http.ResponseWriter, r *http.Request) {
	respond(w, Response{
		Service:   getEnv("SERVICE_NAME", "go-service"),
		Message:   "Admin endpoint - requires admin role",
		Timestamp: time.Now(),
		User:      getUser(r),
	})
}

func getUser(r *http.Request) string {
	// Envoy forwards JWT in header after validation
	auth := r.Header.Get("Authorization")
	if auth != "" {
		return "authenticated-user"
	}
	return "anonymous"
}

func respond(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
