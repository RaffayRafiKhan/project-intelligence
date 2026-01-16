// app/layout.tsx
import './globals.css'; // optional, your global CSS

export const metadata = {
  title: 'Product Intelligence',
  description: 'AI-powered product search platform',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        {children}
      </body>
    </html>
  );
}
