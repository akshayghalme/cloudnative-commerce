package handlers

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/akshayghalme/cloudnative-commerce/services/product-api/models"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

type ProductHandler struct {
	db    *pgxpool.Pool
	redis *redis.Client
	log   *slog.Logger
}

func NewProductHandler(db *pgxpool.Pool, redis *redis.Client, log *slog.Logger) *ProductHandler {
	return &ProductHandler{db: db, redis: redis, log: log}
}

func (h *ProductHandler) List(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	rows, err := h.db.Query(ctx, `
		SELECT id, name, description, price_cents, sku, stock, created_at, updated_at
		FROM products
		ORDER BY created_at DESC
	`)
	if err != nil {
		h.log.Error("failed to list products", "err", err)
		respondError(w, http.StatusInternalServerError, "failed to fetch products")
		return
	}
	defer rows.Close()

	products := []models.Product{}
	for rows.Next() {
		var p models.Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.PriceCents, &p.SKU, &p.Stock, &p.CreatedAt, &p.UpdatedAt); err != nil {
			h.log.Error("failed to scan product row", "err", err)
			respondError(w, http.StatusInternalServerError, "failed to read products")
			return
		}
		products = append(products, p)
	}

	respondJSON(w, http.StatusOK, models.ListProductsResponse{
		Products: products,
		Total:    len(products),
	})
}

func (h *ProductHandler) Get(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	var p models.Product
	err := h.db.QueryRow(ctx, `
		SELECT id, name, description, price_cents, sku, stock, created_at, updated_at
		FROM products WHERE id = $1
	`, id).Scan(&p.ID, &p.Name, &p.Description, &p.PriceCents, &p.SKU, &p.Stock, &p.CreatedAt, &p.UpdatedAt)

	if err == pgx.ErrNoRows {
		respondError(w, http.StatusNotFound, "product not found")
		return
	}
	if err != nil {
		h.log.Error("failed to get product", "id", id, "err", err)
		respondError(w, http.StatusInternalServerError, "failed to fetch product")
		return
	}

	respondJSON(w, http.StatusOK, p)
}

func (h *ProductHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req models.CreateProductRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.Name == "" || req.SKU == "" {
		respondError(w, http.StatusBadRequest, "name and sku are required")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	var p models.Product
	err := h.db.QueryRow(ctx, `
		INSERT INTO products (name, description, price_cents, sku, stock)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, name, description, price_cents, sku, stock, created_at, updated_at
	`, req.Name, req.Description, req.PriceCents, req.SKU, req.Stock).
		Scan(&p.ID, &p.Name, &p.Description, &p.PriceCents, &p.SKU, &p.Stock, &p.CreatedAt, &p.UpdatedAt)

	if err != nil {
		h.log.Error("failed to create product", "err", err)
		respondError(w, http.StatusInternalServerError, "failed to create product")
		return
	}

	h.log.Info("product created", "id", p.ID, "sku", p.SKU)
	respondJSON(w, http.StatusCreated, p)
}

func (h *ProductHandler) Update(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	var req models.UpdateProductRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	var p models.Product
	err := h.db.QueryRow(ctx, `
		UPDATE products
		SET
			name        = COALESCE($2, name),
			description = COALESCE($3, description),
			price_cents = COALESCE($4, price_cents),
			stock       = COALESCE($5, stock),
			updated_at  = NOW()
		WHERE id = $1
		RETURNING id, name, description, price_cents, sku, stock, created_at, updated_at
	`, id, req.Name, req.Description, req.PriceCents, req.Stock).
		Scan(&p.ID, &p.Name, &p.Description, &p.PriceCents, &p.SKU, &p.Stock, &p.CreatedAt, &p.UpdatedAt)

	if err == pgx.ErrNoRows {
		respondError(w, http.StatusNotFound, "product not found")
		return
	}
	if err != nil {
		h.log.Error("failed to update product", "id", id, "err", err)
		respondError(w, http.StatusInternalServerError, "failed to update product")
		return
	}

	// Invalidate cache on update
	h.redis.Del(ctx, "product:"+id)

	h.log.Info("product updated", "id", id)
	respondJSON(w, http.StatusOK, p)
}

func (h *ProductHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	result, err := h.db.Exec(ctx, "DELETE FROM products WHERE id = $1", id)
	if err != nil {
		h.log.Error("failed to delete product", "id", id, "err", err)
		respondError(w, http.StatusInternalServerError, "failed to delete product")
		return
	}
	if result.RowsAffected() == 0 {
		respondError(w, http.StatusNotFound, "product not found")
		return
	}

	h.redis.Del(ctx, "product:"+id)
	h.log.Info("product deleted", "id", id)
	w.WriteHeader(http.StatusNoContent)
}

func respondJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func respondError(w http.ResponseWriter, status int, msg string) {
	respondJSON(w, status, map[string]string{"error": msg})
}
