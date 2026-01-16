import { NextResponse } from "next/server";

export async function POST(req: Request) {
  const body = await req.json();
  const { query } = body;

  if (!query) {
    return NextResponse.json({ error: "Missing query" }, { status: 400 });
  }

  return NextResponse.json({
    query,
    message: "Search endpoint working"
  });
}
