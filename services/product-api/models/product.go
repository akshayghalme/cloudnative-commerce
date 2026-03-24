package models

import "time"

type Product struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	PriceCents  int64     `json:"price_cents"` // stored in cents to avoid float precision issues
	SKU         string    `json:"sku"`
	Stock       int       `json:"stock"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type CreateProductRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	PriceCents  int64  `json:"price_cents"`
	SKU         string `json:"sku"`
	Stock       int    `json:"stock"`
}

type UpdateProductRequest struct {
	Name        *string `json:"name,omitempty"`
	Description *string `json:"description,omitempty"`
	PriceCents  *int64  `json:"price_cents,omitempty"`
	Stock       *int    `json:"stock,omitempty"`
}

type ListProductsResponse struct {
	Products []Product `json:"products"`
	Total    int       `json:"total"`
}
