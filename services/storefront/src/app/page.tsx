import ProductGrid from '@/components/ProductGrid'

export default function Home() {
  return (
    <main style={{ maxWidth: '1200px', margin: '0 auto', padding: '2rem 1rem' }}>
      <header style={{ marginBottom: '2rem' }}>
        <h1 style={{ fontSize: '1.75rem', fontWeight: 700 }}>Products</h1>
      </header>
      <ProductGrid />
    </main>
  )
}
