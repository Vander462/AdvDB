import './globals.css';

export const metadata = { title: 'College Maintenance Requests' };

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
