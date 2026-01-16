// app/layout.tsx
import './globals.css'; // optional, create this file if you want global styles

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
