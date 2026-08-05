#!/usr/bin/env python3
"""Wire Recharge App Store products into RevenueCat.

Usage: RC_KEY=sk_... python3 scripts/rc-setup.py
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

BASE = "https://api.revenuecat.com/v2"
BUNDLE_ID = "com.jackwallner.recharge"
PRODUCTS = (
    ("com.jackwallner.recharge.monthly", "Monthly", "subscription", "$rc_monthly"),
    ("com.jackwallner.recharge.yearly", "Yearly", "subscription", "$rc_annual"),
    ("com.jackwallner.recharge.pro.lifetime", "Lifetime", "one_time", "$rc_lifetime"),
)


def request(method: str, path: str, body: dict | None = None) -> dict:
    key = os.environ.get("RC_KEY")
    if not key:
        raise SystemExit("error: set RC_KEY")
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data=data, timeout=120) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()[:800]
        raise RuntimeError(f"{method} {path} -> {error.code}: {detail}") from error


def main() -> None:
    projects = request("GET", "/projects")["items"]
    project = next(project for project in projects if project["name"].lower() in {"recharge", "recharge: recovery time"})
    project_id = project["id"]
    apps = request("GET", f"/projects/{project_id}/apps")["items"]
    app = next(
        app
        for app in apps
        if app.get("app_store", {}).get("bundle_id") == BUNDLE_ID
    )
    app_id = app["id"]
    print(f"project: {project['name']}")
    print(f"app: {app['name']}")

    existing_products = request(
        "GET", f"/projects/{project_id}/products?limit=100"
    )["items"]
    products_by_identifier = {
        product["store_identifier"]: product for product in existing_products
    }
    configured_products: dict[str, dict] = {}
    for identifier, display_name, product_type, _ in PRODUCTS:
        product = products_by_identifier.get(identifier)
        if product is None:
            product = request(
                "POST",
                f"/projects/{project_id}/products",
                {
                    "store_identifier": identifier,
                    "app_id": app_id,
                    "type": product_type,
                    "display_name": display_name,
                },
            )
            print(f"created product: {identifier}")
        else:
            print(f"product exists: {identifier}")
        configured_products[identifier] = product

    entitlements = request("GET", f"/projects/{project_id}/entitlements")["items"]
    entitlement = next(
        (
            entitlement
            for entitlement in entitlements
            if entitlement["lookup_key"] in {"pro", "V02 Max Pro", "Recharge Pro", "Recharge Pro"}
        ),
        None,
    )
    if entitlement is None:
        entitlement = request(
            "POST",
            f"/projects/{project_id}/entitlements",
            {"lookup_key": "pro", "display_name": "Recharge Pro"},
        )
        print("created entitlement: pro")

    attached = request(
        "GET",
        f"/projects/{project_id}/entitlements/{entitlement['id']}/products?limit=100",
    )["items"]
    attached_ids = {product["id"] for product in attached}
    missing_ids = [
        product["id"]
        for product in configured_products.values()
        if product["id"] not in attached_ids
    ]
    if missing_ids:
        request(
            "POST",
            f"/projects/{project_id}/entitlements/{entitlement['id']}/actions/attach_products",
            {"product_ids": missing_ids},
        )
        print(f"attached {len(missing_ids)} products to {entitlement['lookup_key']}")

    offerings = request("GET", f"/projects/{project_id}/offerings")["items"]
    offering = next(offering for offering in offerings if offering.get("is_current"))
    packages = request(
        "GET", f"/projects/{project_id}/offerings/{offering['id']}/packages?limit=100"
    )["items"]
    packages_by_key = {package["lookup_key"]: package for package in packages}
    for identifier, _, _, package_key in PRODUCTS:
        package = packages_by_key[package_key]
        attached_items = request(
            "GET", f"/projects/{project_id}/packages/{package['id']}/products?limit=100"
        )["items"]
        attached_product_ids = {item["product"]["id"] for item in attached_items}
        product = configured_products[identifier]
        if product["id"] in attached_product_ids:
            continue
        request(
            "POST",
            f"/projects/{project_id}/packages/{package['id']}/actions/attach_products",
            {
                "products": [
                    {"product_id": product["id"], "eligibility_criteria": "all"}
                ]
            },
        )
        print(f"attached {identifier} to {package_key}")

    keys = request(
        "GET", f"/projects/{project_id}/apps/{app_id}/public_api_keys"
    )["items"]
    production_key = next(key["key"] for key in keys if key["environment"] == "production")
    print(f"public SDK key: {production_key}")
    print("done")


if __name__ == "__main__":
    main()
