interface Product {
  id: string
  name: string
  description: string
  price_cents: number
  sku: string
  stock: number
}

function formatPrice(cents: number): string {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
  }).format(cents / 100)
}

export default function ProductCard({ product }: { product: Product }) {
  return (
    <div style={{
      background: '#fff',
      border: '1px solid #e5e7eb',
      borderRadius: '8px',
      padding: '1.25rem',
      display: 'flex',
      flexDirection: 'column',
      gap: '0.5rem',
    }}>
      <h2 style={{ fontSize: '1rem', fontWeight: 600 }}>{product.name}</h2>
      <p style={{ fontSize: '0.875rem', color: '#6b7280', flexGrow: 1 }}>{product.description}</p>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '0.5rem' }}>
        <span style={{ fontWeight: 700, fontSize: '1.1rem' }}>{formatPrice(product.price_cents)}</span>
        <span style={{ fontSize: '0.75rem', color: product.stock > 0 ? '#16a34a' : '#dc2626' }}>
          {product.stock > 0 ? `${product.stock} in stock` : 'Out of stock'}
        </span>
      </div>
      <p style={{ fontSize: '0.7rem', color: '#9ca3af' }}>SKU: {product.sku}</p>
    </div>
  )
}
