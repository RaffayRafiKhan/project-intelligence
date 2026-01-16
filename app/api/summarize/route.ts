import { NextResponse } from "next/server";

export async function POST(req: Request) {
  const body = await req.json();

  return NextResponse.json({
    pros: ["Example pro"],
    cons: ["Example con"],
    scores: {
      quality: 8,
      durability: 7,
      valueForMoney: 6
    }
  });
}
