#!/usr/bin/env python3
"""يولّد مفاتيح JWT محلية (anon / service_role) لبيئة الاختبار فقط."""
import base64, hashlib, hmac, json, sys
secret = sys.argv[1]
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
def jwt(role):
    h = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    p = b64(json.dumps({"role": role, "iss": "supabase", "iat": 1700000000, "exp": 2000000000}).encode())
    s = b64(hmac.new(secret.encode(), f"{h}.{p}".encode(), hashlib.sha256).digest())
    return f"{h}.{p}.{s}"
print(f"ANON_KEY={jwt('anon')}")
print(f"SERVICE_KEY={jwt('service_role')}")
