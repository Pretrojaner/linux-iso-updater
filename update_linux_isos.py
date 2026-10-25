#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Linux ISO Auto-Updater & Ventoy Sync Tool (Linux Edition)
Version: 2.3.0-linux

Funktionen:
1. Prüft & lädt neueste Linux ISOs herunter, verifiziert SHA256/SHA512/MD5-Hashes & archiviert veraltete Dateien.
2. Ermöglicht interaktive Gruppenauswahl (Desktop, Server, Security, Rescue, BSD) mit Mehrfachwahl.
3. Erkennt Ventoy-Wechseldatenträger, berechnet vorab den Speicherbedarf, synchronisiert ISOs mit Live-Fortschritt
   und richtet 1080p Themes inklusive Dir-/TreeView-Modus ein.
4. Optionale automatisierte Ventoy CLI-Installation auf Ziel-Laufwerke.
"""

import argparse
import bz2
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urljoin

try:
    import requests
except ImportError:
    print("[FEHLER] Das Python-Paket 'requests' ist nicht installiert.")
    print("Bitte führe './update-linux-isos.sh' aus oder installiere es via 'pip install requests Pillow'.")
    sys.exit(1)

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("[FEHLER] Das Python-Paket 'Pillow' ist nicht installiert.")
    print("Bitte führe './update-linux-isos.sh' aus oder installiere es via 'pip install requests Pillow'.")
    sys.exit(1)

# ==============================================================================
# GLOBALE KONSTANTEN
# ==============================================================================
SCRIPT_VERSION = "2.3.0-linux"
DEFAULT_LOG_FILE = "update-linux-isos.log"
DEFAULT_LOCK_FILE = "/tmp/linux_iso_auto_updater.lock"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
CURL_USER_AGENT = "curl/8.4.0"

CATEGORY_ORDER = [
    "01_Desktop-Linux",
    "02_Enterprise-Server",
    "03_Security-Pentest",
    "04_Rescue-Systeme",
    "05_BSD-Unix",
]


class Colors:
    """ANSI Escape Codes für farbige Terminalausgaben."""
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    MAGENTA = "\033[95m"
    CYAN = "\033[96m"
    WHITE = "\033[97m"
    DARK_GRAY = "\033[90m"


class Logger:
    """Thread-/Prozess-sicheres Logging mit Konsole und Logdatei."""

    def __init__(self, log_path: Path):
        self.log_path = log_path

    def _write_file(self, formatted: str) -> None:
        try:
            with open(self.log_path, "a", encoding="utf-8") as f:
                f.write(formatted + "\n")
        except Exception:
            pass

    def log(self, message: str, color: str = Colors.WHITE, level: str = "INFO") -> None:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        formatted = f"[{timestamp}] [{level}] {message}"
        print(f"{color}{formatted}{Colors.RESET}")
        self._write_file(formatted)

    def detail(self, message: str, color: str = Colors.DARK_GRAY) -> None:
        formatted = f"   {message}"
        print(f"{color}{formatted}{Colors.RESET}")
        self._write_file(formatted)

    def raw(self, message: str, color: str = Colors.WHITE) -> None:
        print(f"{color}{message}{Colors.RESET}")
        self._write_file(message)

    def clear_screen_distro(self, current: int, total: int, name: str) -> None:
        os.system("clear")
        cols = shutil.get_terminal_size(fallback=(80, 24)).columns
        banner_len = min(90, max(40, cols - 1))
        banner_border = "=" * banner_len
        remaining = total - current
        header_text = f" DISTRO-FORTSCHRITT: {current} von {total} verarbeitet | {remaining} verbleibend | Aktuell: {name}"
        if len(header_text) > cols - 1:
            header_text = header_text[: cols - 4] + "..."
        print(f"{Colors.CYAN}{banner_border}{Colors.RESET}")
        print(f"{Colors.YELLOW}{header_text}{Colors.RESET}")
        print(f"{Colors.CYAN}{banner_border}{Colors.RESET}")
        self.log(f"[{current}/{total}] Prüfe Distribution: {name}", color=Colors.YELLOW, level="CHECK")

    def clear_screen_ventoy_copy(self, current: int, total: int, filename: str, size_mb: float) -> None:
        os.system("clear")
        cols = shutil.get_terminal_size(fallback=(80, 24)).columns
        banner_len = min(90, max(40, cols - 1))
        banner_border = "=" * banner_len
        remaining = total - current
        header_text = f" VENTOY-KOPIERSTATUS: {current} von {total} ISOs | {remaining} verbleibend | Aktuell: {filename} ({size_mb:.2f} MB)"
        if len(header_text) > cols - 1:
            header_text = header_text[: cols - 4] + "..."
        print(f"{Colors.CYAN}{banner_border}{Colors.RESET}")
        print(f"{Colors.YELLOW}{header_text}{Colors.RESET}")
        print(f"{Colors.CYAN}{banner_border}{Colors.RESET}")


class SingleInstanceLock:
    """Verhindert Mehrfachstarts mittels fcntl.flock."""

    def __init__(self, lock_file_path: str = DEFAULT_LOCK_FILE):
        self.lock_file_path = lock_file_path
        self.fp = None

    def acquire(self) -> bool:
        try:
            self.fp = open(self.lock_file_path, "w")
            fcntl.flock(self.fp.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return True
        except (IOError, BlockingIOError):
            return False

    def release(self) -> None:
        if self.fp:
            try:
                fcntl.flock(self.fp.fileno(), fcntl.LOCK_UN)
                self.fp.close()
                if os.path.exists(self.lock_file_path):
                    os.unlink(self.lock_file_path)
            except Exception:
                pass


def version_sort_key(ver_str: Any) -> Tuple[int, ...]:
    """Wandelt Versionszeichenketten für numerisches Sortieren in Tuple um."""
    parts = re.findall(r"\d+", str(ver_str))
    return tuple(int(p) for p in parts) if parts else (0,)


def format_progress_bar(prefix: str, current_bytes: int, total_bytes: int, speed_bytes_sec: float) -> str:
    """
    Erstellt eine einzeilige Fortschrittsanzeige, die sich dynamisch an die Terminalbreite anpasst
    und niemals umbricht.
    """
    cols = shutil.get_terminal_size(fallback=(80, 24)).columns
    max_len = max(cols - 1, 30)

    speed_mb = speed_bytes_sec / (1024 * 1024)
    trans_mb = current_bytes / (1024 * 1024)

    if total_bytes > 0:
        percent = min(100.0, (current_bytes / total_bytes) * 100.0)
        total_mb = total_bytes / (1024 * 1024)
        stats_full = f"{percent:5.1f}% | {trans_mb:7.2f} / {total_mb:7.2f} MB | {speed_mb:5.2f} MB/s"
        stats_short = f"{percent:5.1f}% | {trans_mb:.1f}/{total_mb:.1f} MB | {speed_mb:.1f} MB/s"

        fixed_len = len(prefix) + len(stats_full) + 4  # 'prefix [bar] stats'
        avail = max_len - fixed_len
        if avail >= 10:
            bar_width = min(25, avail)
            completed = int((percent / 100.0) * bar_width)
            bar_str = "=" * completed + "-" * (bar_width - completed)
            line = f"{prefix} [{bar_str}] {stats_full}"
        else:
            fixed_short = len(prefix) + len(stats_short) + 4
            avail_short = max_len - fixed_short
            if avail_short >= 8:
                bar_width = min(20, avail_short)
                completed = int((percent / 100.0) * bar_width)
                bar_str = "=" * completed + "-" * (bar_width - completed)
                line = f"{prefix} [{bar_str}] {stats_short}"
            elif max_len >= len(prefix) + len(stats_short) + 1:
                line = f"{prefix} {stats_short}"
            else:
                line = f"{prefix} {percent:5.1f}% | {trans_mb:.1f} MB"
    else:
        line = f"{prefix} {trans_mb:7.2f} MB | {speed_mb:5.2f} MB/s"

    return line[:max_len]


def format_duration(seconds: float) -> str:
    """Formatiert Sekunden in eine lesbare Zeichenkette wie '1h 12m 30s', '3m 45s' oder '12.4s'."""
    sec = int(round(seconds))
    if sec < 60:
        return f"{seconds:.1f}s" if seconds < 10 else f"{sec}s"
    minutes = sec // 60
    remaining_sec = sec % 60
    if minutes < 60:
        return f"{minutes}m {remaining_sec:02d}s"
    hours = minutes // 60
    remaining_min = minutes % 60
    return f"{hours}h {remaining_min:02d}m {remaining_sec:02d}s"


class DownloadResult:
    """Ergebnis eines HTTP-Downloads mit Metriken zu Dateigröße, Dauer und Geschwindigkeit."""

    def __init__(self, downloaded_bytes: int, elapsed_seconds: float):
        self.bytes = int(downloaded_bytes)
        self.seconds = max(elapsed_seconds, 0.001)
        self.size_mb = self.bytes / (1024 * 1024)
        self.speed_bytes_sec = self.bytes / self.seconds
        self.speed_mbs = self.speed_bytes_sec / (1024 * 1024)
        self.speed_mbits = (self.bytes * 8) / (self.seconds * 1_000_000)

    @property
    def duration_str(self) -> str:
        return format_duration(self.seconds)

    def __int__(self) -> int:
        return self.bytes

    def __iter__(self):
        return iter((self.bytes, self.seconds))

    def __repr__(self) -> str:
        return f"<DownloadResult {self.size_mb:.2f} MB in {self.duration_str} ({self.speed_mbs:.2f} MB/s)>"


# ==============================================================================
# HTTP & DOWNLOAD MANAGER
# ==============================================================================
class DownloadManager:
    """Verwaltet Web-Content-Abrufe und Streaming-Downloads."""

    def __init__(self, logger: Logger):
        self.logger = logger
        self.session = requests.Session()

    def get_web_content(self, uri: str, timeout: int = 15) -> Optional[str]:
        headers = {
            "User-Agent": CURL_USER_AGENT if "sourceforge.net" in uri else USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,text/plain,*/*;q=0.8",
        }
        try:
            with self.session.get(uri, headers=headers, stream=True, timeout=timeout) as resp:
                if resp.status_code == 200:
                    cl = int(resp.headers.get("Content-Length", 0))
                    ct = resp.headers.get("Content-Type", "").lower()
                    # Wenn Datei > 2 MB oder Binärarchiv/ISO, Download ablehnen
                    if cl > 2 * 1024 * 1024 or any(b in ct for b in ["octet-stream", "x-iso", "bzip2", "gzip", "zip", "image/"]):
                        return None
                    # Maximal 2 MB Text lesen
                    content_bytes = resp.raw.read(2 * 1024 * 1024, decode_content=True)
                    return content_bytes.decode("utf-8", errors="replace")
        except Exception:
            pass

        # Fallback über systemeigenes curl mit Größen-Limit (max 2 MB)
        try:
            cmd = ["curl", "-sL", "-A", headers["User-Agent"], "--max-time", str(timeout), "--max-filesize", "2097152", uri]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout
        except Exception:
            pass
        return None

    def get_online_file_size(self, url: str, timeout: int = 10) -> int:
        headers = {
            "User-Agent": CURL_USER_AGENT if "sourceforge.net" in url else USER_AGENT,
        }
        try:
            resp = self.session.head(url, headers=headers, allow_redirects=True, timeout=timeout)
            if resp.status_code == 200 and "Content-Length" in resp.headers:
                length = int(resp.headers["Content-Length"])
                if length >= 1024 * 1024:
                    return length
            # Einige Server antworten auf HEAD nicht mit Content-Length
            resp_get = self.session.get(url, headers=headers, stream=True, timeout=timeout)
            if resp_get.status_code == 200 and "Content-Length" in resp_get.headers:
                length = int(resp_get.headers["Content-Length"])
                resp_get.close()
                if length >= 1024 * 1024:
                    return length
        except Exception:
            pass

        # Fallback über curl
        try:
            cmd = ["curl", "-sIL", "-A", headers["User-Agent"], "--max-time", str(timeout), url]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            if res.returncode == 0:
                matches = re.findall(r"(?i)content-length:\s*(\d+)", res.stdout)
                if matches:
                    length = int(matches[-1])
                    if length >= 1024 * 1024:
                        return length
        except Exception:
            pass
        return 0

    def download_file(self, url: str, dest_path: Path, filename: str) -> DownloadResult:
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        headers = {
            "User-Agent": CURL_USER_AGENT if "sourceforge.net" in url else USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        }

        temp_dest = dest_path.with_suffix(dest_path.suffix + ".part")
        try:
            with self.session.get(url, headers=headers, stream=True, timeout=30) as resp:
                resp.raise_for_status()
                total_bytes = int(resp.headers.get("Content-Length", -1))

                start_time = time.monotonic()
                last_report = 0.0
                total_read = 0
                is_tty = sys.stdout.isatty()
                report_interval = 0.2 if is_tty else 5.0

                with open(temp_dest, "wb") as f:
                    for chunk in resp.iter_content(chunk_size=131072):
                        if not chunk:
                            continue
                        f.write(chunk)
                        total_read += len(chunk)

                        now = time.monotonic()
                        if now - last_report >= report_interval or total_read == total_bytes:
                            elapsed = max(now - start_time, 0.001)
                            speed_bytes_sec = total_read / elapsed
                            status = format_progress_bar("   [LADEN]", total_read, total_bytes, speed_bytes_sec)

                            if is_tty:
                                sys.stdout.write(f"\r\033[K{Colors.CYAN}{status}{Colors.RESET}")
                                sys.stdout.flush()
                            else:
                                sys.stdout.write(f"{status}\n")
                                sys.stdout.flush()
                            last_report = now

                if is_tty:
                    sys.stdout.write("\n")
                    sys.stdout.flush()

                if total_bytes > 0 and total_read < total_bytes:
                    raise IOError(f"Download unvollständig: {total_read} von {total_bytes} Bytes empfangen.")

                if dest_path.exists():
                    dest_path.unlink()
                temp_dest.rename(dest_path)
                elapsed_total = max(time.monotonic() - start_time, 0.001)
                return DownloadResult(total_read, elapsed_total)

        except Exception as e:
            if sys.stdout.isatty():
                sys.stdout.write("\n")
                sys.stdout.flush()
            if temp_dest.exists():
                try:
                    temp_dest.unlink()
                except Exception:
                    pass
            # Fallback mit curl falls Python requests scheitert
            try:
                self.logger.raw(f"\n   [DOWNLOAD FALLBACK] Nutze curl für {filename}...", color=Colors.YELLOW)
                curl_start = time.monotonic()
                curl_cmd = ["curl", "-L", "-A", headers["User-Agent"], "--progress-bar", "-o", str(dest_path), url]
                subprocess.run(curl_cmd, check=True)
                curl_elapsed = max(time.monotonic() - curl_start, 0.001)
                if dest_path.exists() and dest_path.stat().st_size > 1024 * 1024:
                    return DownloadResult(dest_path.stat().st_size, curl_elapsed)
            except Exception:
                pass
            raise e


# ==============================================================================
# CHECKSUM VERIFICATION & ARCHIV-MANAGER
# ==============================================================================
class ChecksumVerifier:
    """Prüft SHA256, SHA512 und MD5 Prüfsummen mit negativen Lookarounds."""

    def __init__(self, download_mgr: DownloadManager, logger: Logger):
        self.dm = download_mgr
        self.logger = logger

    def verify_iso_checksum(
        self, file_path: Path, download_url: str, filename: str, explicit_checksum_url: Optional[str] = None
    ) -> bool:
        expected_hash = None
        hash_algo = None

        # Basis-URL ohne Endungen wie .iso, .bz2, .gz etc. ermitteln
        base_url = re.sub(r"(\.iso)?(\.bz2|\.gz|\.xz|\.zip)?$", "", download_url, flags=re.I)

        sha512_candidates = [
            f"{base_url}.iso.sha512sum",
            f"{base_url}.iso.sha512",
            f"{base_url}.sha512sum",
            f"{base_url}.sha512",
            f"{download_url}.sha512sum",
            f"{download_url}.sha512",
        ]
        if explicit_checksum_url and "sha512" in explicit_checksum_url.lower():
            sha512_candidates.insert(0, explicit_checksum_url)

        sha256_candidates = [
            f"{base_url}.iso.sha256",
            f"{base_url}.iso.sha256sum",
            f"{base_url}.iso.SHA256",
            f"{base_url}.sha256",
            f"{base_url}.sha256sum",
            f"{download_url}.sha256",
            f"{download_url}.sha256sum",
            f"{download_url}.SHA256",
        ]
        if explicit_checksum_url and not any(k in explicit_checksum_url.lower() for k in ["sha512", "md5"]):
            sha256_candidates.insert(0, explicit_checksum_url)

        md5_candidates = [
            f"{base_url}.iso.md5",
            f"{base_url}.md5",
            f"{download_url}.md5",
        ]
        if explicit_checksum_url and "md5" in explicit_checksum_url.lower():
            md5_candidates.insert(0, explicit_checksum_url)

        def clean_candidates(c_list: List[str]) -> List[str]:
            res = []
            for c in c_list:
                if not c or c == download_url:
                    continue
                # Niemals ISOs oder Archive selbst als Prüfsummen-URL aufrufen
                if re.search(r"\.(iso|bz2|gz|xz|tar|zip|img)$", c, re.I):
                    continue
                if c not in res:
                    res.append(c)
            return res

        sha512_candidates = clean_candidates(sha512_candidates)
        sha256_candidates = clean_candidates(sha256_candidates)
        md5_candidates = clean_candidates(md5_candidates)

        algo_order = ["SHA256", "SHA512", "MD5"]
        if explicit_checksum_url:
            if "sha512" in explicit_checksum_url.lower():
                algo_order = ["SHA512", "SHA256", "MD5"]
            elif "md5" in explicit_checksum_url.lower():
                algo_order = ["MD5", "SHA256", "SHA512"]

        self.logger.detail(f"Suche Online-Prüfsumme für {filename}...", color=Colors.DARK_GRAY)

        for algo in algo_order:
            if expected_hash:
                break
            candidates = {
                "SHA512": sha512_candidates,
                "SHA256": sha256_candidates,
                "MD5": md5_candidates,
            }[algo]
            hex_len = {"SHA512": 128, "SHA256": 64, "MD5": 32}[algo]

            # Striktes Pattern mit negativen Lookarounds zur Vermeidung von Teilstring-Fehlern
            regex_with_filename_1 = re.compile(
                rf"^.*{re.escape(filename)}.*?(?<![a-fA-F0-9])([a-fA-F0-9]{{{hex_len}}})(?![a-fA-F0-9])",
                re.MULTILINE,
            )
            regex_with_filename_2 = re.compile(
                rf"^(?<![a-fA-F0-9])([a-fA-F0-9]{{{hex_len}}})(?![a-fA-F0-9])\s+.*?{re.escape(filename)}",
                re.MULTILINE,
            )
            regex_generic = re.compile(rf"(?<![a-fA-F0-9])([a-fA-F0-9]{{{hex_len}}})(?![a-fA-F0-9])")

            for c_url in candidates:
                content = self.dm.get_web_content(c_url, timeout=5)
                if content:
                    m1 = regex_with_filename_1.search(content)
                    if m1:
                        expected_hash = m1.group(1).lower()
                        hash_algo = algo
                        break
                    m2 = regex_with_filename_2.search(content)
                    if m2:
                        expected_hash = m2.group(1).lower()
                        hash_algo = algo
                        break
                    # regex_generic nur anwenden, wenn es sich nicht um eine HTML-Seite handelt (z.B. Sourceforge 404/Fehlerseite)
                    is_html = bool(re.search(r"^\s*<(!doctype|html)", content, re.I))
                    if not is_html:
                        m3 = regex_generic.search(content)
                        if m3:
                            expected_hash = m3.group(1).lower()
                            hash_algo = algo
                            break

        if not expected_hash:
            self.logger.detail(
                f"Keine Online-Prüfsumme gefunden für {filename}. Überspringe Hash-Verifikation.",
                color=Colors.DARK_GRAY,
            )
            return True

        file_mb = file_path.stat().st_size / (1024 * 1024)
        self.logger.detail(f"Erwarteter Hash ({hash_algo}): {expected_hash}", color=Colors.DARK_GRAY)
        self.logger.detail(f"Berechne lokalen {hash_algo}-Hash ({file_mb:.2f} MB)... Bitte warten.", color=Colors.DARK_GRAY)

        hasher = {
            "SHA512": hashlib.sha512(),
            "SHA256": hashlib.sha256(),
            "MD5": hashlib.md5(),
        }[hash_algo]

        try:
            with open(file_path, "rb") as f:
                while chunk := f.read(1024 * 1024):
                    hasher.update(chunk)
            actual_hash = hasher.hexdigest().lower()
            self.logger.detail(f"Berechneter Hash: {actual_hash}", color=Colors.DARK_GRAY)

            if actual_hash == expected_hash:
                self.logger.detail(f"{hash_algo}-Prüfsumme VERIFIZIERT: OK", color=Colors.GREEN)
                return True
            else:
                self.logger.log(
                    f"{hash_algo}-Prüfsumme FALSCH! Erwartet: {expected_hash} | Berechnet: {actual_hash}",
                    color=Colors.RED,
                    level="FEHLER",
                )
                return False
        except Exception as e:
            self.logger.log(f"Fehler bei der Berechnung der Prüfsumme: {e}", color=Colors.RED, level="FEHLER")
            return True


def decompress_bz2(bz2_path: Path, dest_iso_path: Path) -> bool:
    """Dekomprimiert .bz2-Archive mit dem integrierten Python bz2-Modul."""
    dest_iso_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with bz2.BZ2File(bz2_path, "rb") as src, open(dest_iso_path, "wb") as dst:
            shutil.copyfileobj(src, dst, length=1024 * 1024)
        if dest_iso_path.exists() and dest_iso_path.stat().st_size > 1024 * 1024:
            return True
    except Exception:
        pass

    # Fallback tar / bzip2
    try:
        subprocess.run(["tar", "-xf", str(bz2_path), "-C", str(dest_iso_path.parent)], check=True)
        if dest_iso_path.exists():
            return True
    except Exception:
        pass
    return False


# ==============================================================================
# DISTRIBUTIONS SCRAPING ENGINE (ALLE 45 DISTROS)
# ==============================================================================
class DistroScraperEngine:
    """Implementiert native Web-Scraper für alle 45 Distributionen."""

    def __init__(self, download_mgr: DownloadManager):
        self.dm = download_mgr

    def get_latest(self, item: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        name = item.get("Name", "")
        method_name = f"scrape_{re.sub(r'[^a-zA-Z0-9_]', '', name.lower().replace(' ', '_'))}"
        if hasattr(self, method_name):
            try:
                res = getattr(self, method_name)()
                if res and res.get("Filename") and res.get("Url"):
                    return res
            except Exception:
                pass

        # Fallback falls direkte Url hinterlegt ist
        if item.get("Url"):
            direct_url = item["Url"]
            clean_url = direct_url.split("?")[0]
            fn = Path(clean_url).name
            if not fn or not fn.endswith(".iso"):
                fn = f"{name.replace(' ', '_')}.iso"
            vm = re.search(r"(\d+\.\d+(\.\d+)?)", fn)
            ver = vm.group(1) if vm else "Direkt"
            return {"Version": ver, "Url": direct_url, "Filename": fn}

        return None

    # --- 01 Desktop Linux ---
    def scrape_cachyos(self) -> Optional[Dict[str, Any]]:
        for u in ["https://mirror.cachyos.org/ISO/desktop/", "https://cdn.cachyos.org/ISO/desktop/"]:
            html = self.dm.get_web_content(u)
            if html:
                matches = re.findall(r'href="(\d+)/"', html)
                if matches:
                    latest = sorted(matches, key=int, reverse=True)[0]
                    fn = f"cachyos-desktop-linux-{latest}.iso"
                    return {"Version": latest, "Url": f"{u}{latest}/{fn}", "Filename": fn}
        return None

    def scrape_garuda_linux(self) -> Optional[Dict[str, Any]]:
        html = self.dm.get_web_content("https://iso.builds.garudalinux.org/iso/garuda/dr460nized/")
        if html:
            matches = re.findall(r'href="(\d+)/"', html)
            if matches:
                latest = sorted(matches, key=int, reverse=True)[0]
                sub = self.dm.get_web_content(f"https://iso.builds.garudalinux.org/iso/garuda/dr460nized/{latest}/")
                if sub:
                    m = re.search(r'href="(garuda-dr460nized-[^"]*?(\d{6})\.iso)"', sub)
                    if m:
                        return {
                            "Version": m.group(2),
                            "Url": f"https://iso.builds.garudalinux.org/iso/garuda/dr460nized/{latest}/{m.group(1)}",
                            "Filename": m.group(1),
                        }
        return None

    def scrape_linux_mint_cinnamon(self) -> Optional[Dict[str, Any]]:
        for base in [
            "https://ftp.fau.de/mint/iso/stable/",
            "https://mirror.netcologne.de/linuxmint/iso/stable/",
            "https://mirrors.edge.kernel.org/linuxmint/stable/",
        ]:
            html = self.dm.get_web_content(base)
            if html:
                raw_versions = [m[0] for m in re.findall(r'href="(\d+(\.\d+)*)/"', html)]
                sorted_vers = sorted(raw_versions, key=version_sort_key, reverse=True)[:3]
                for v in sorted_vers:
                    sub = self.dm.get_web_content(f"{base}{v}/")
                    if sub:
                        m = re.search(r'href="(linuxmint-[^"]+-cinnamon-64bit\.iso)"', sub)
                        if m:
                            return {"Version": v, "Url": f"{base}{v}/{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_omarchy(self) -> Optional[Dict[str, Any]]:
        api = self.dm.get_web_content("https://api.github.com/repos/omacom/omarchy/releases/latest")
        if api:
            try:
                rel = json.loads(api)
                tag = rel["tag_name"].lstrip("v")
                iso_url = f"https://iso.omarchy.org/omarchy-{tag}.iso"
                fn = f"omarchy-{tag}.iso"
                for a in rel.get("assets", []):
                    if a.get("name", "").endswith(".iso"):
                        iso_url = a["browser_download_url"]
                        fn = a["name"]
                        break
                return {"Version": tag, "Url": iso_url, "Filename": fn}
            except Exception:
                pass
        html = self.dm.get_web_content("https://github.com/omacom/omarchy/releases")
        if html:
            m = re.search(r"omarchy-(\d+\.\d+(\.\d+)?)\.iso", html)
            if m:
                ver = m.group(1)
                return {"Version": ver, "Url": f"https://iso.omarchy.org/omarchy-{ver}.iso", "Filename": f"omarchy-{ver}.iso"}
        return None

    def scrape_ubuntu_desktop(self) -> Optional[Dict[str, Any]]:
        base = "https://ftp.halifax.rwth-aachen.de/ubuntu-releases/"
        html = self.dm.get_web_content(base)
        if html:
            matches = [m[0] for m in re.findall(r'href="(\d+\.\d+(\.\d+)?)/"', html)]
            for v in sorted(matches, key=version_sort_key, reverse=True)[:3]:
                sub = self.dm.get_web_content(f"{base}{v}/")
                if sub:
                    m = re.search(r'href="(ubuntu-\d+\.\d+(\.\d+)?-desktop-amd64\.iso)"', sub)
                    if m:
                        return {"Version": v, "Url": f"{base}{v}/{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_ubuntu_cinnamon(self) -> Optional[Dict[str, Any]]:
        base = "https://cdimage.ubuntu.com/ubuntucinnamon/releases/"
        html = self.dm.get_web_content(base)
        if html:
            matches = [m[0] for m in re.findall(r'href="(\d+\.\d+(\.\d+)?)/"', html)]
            for v in sorted(matches, key=version_sort_key, reverse=True)[:3]:
                for sub_dir in [f"{base}{v}/release/", f"{base}{v}/"]:
                    sub = self.dm.get_web_content(sub_dir)
                    if sub:
                        m = re.search(r'href="(ubuntucinnamon-[^"]+-desktop-amd64\.iso)"', sub)
                        if m:
                            return {"Version": v, "Url": f"{sub_dir}{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_zorin_os_education(self) -> Optional[Dict[str, Any]]:
        html = self.dm.get_web_content("https://zorin.com/os/download/")
        main_ver = "18"
        if html:
            m = re.search(r"/os/download/(\d+)/education/", html)
            if m:
                main_ver = m.group(1)
        dl = self.dm.get_web_content(f"https://zorin.com/os/download/{main_ver}/education/")
        if dl:
            m = re.search(r'href="(https://[^"]*?Zorin-OS-(\d+(\.\d+)?)-Education-64-bit\.iso)"', dl)
            if m:
                return {
                    "Version": m.group(2),
                    "Url": m.group(1),
                    "Filename": f"Zorin-OS-{m.group(2)}-Education-64-bit.iso",
                }
        return None

    def scrape_alpine_linux(self) -> Optional[Dict[str, Any]]:
        html = self.dm.get_web_content("https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/")
        if html:
            m = re.search(r'href="(alpine-standard-(\d+\.\d+\.\d+)-x86_64\.iso)"', html)
            if m:
                return {
                    "Version": m.group(2),
                    "Url": f"https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/{m.group(1)}",
                    "Filename": m.group(1),
                }
        return None

    def scrape_arch_linux(self) -> Optional[Dict[str, Any]]:
        mirrors = [
            "https://ftp.halifax.rwth-aachen.de/archlinux/iso/latest/",
            "https://geo.mirror.pkgbuild.com/iso/latest/",
        ]
        for base in mirrors:
            html = self.dm.get_web_content(base)
            if html:
                m = re.search(r'href=[\"\'](archlinux-(\d{4}\.\d{2}\.\d{2})-x86_64\.iso)[\"\']', html)
                if m:
                    return {
                        "Version": m.group(2),
                        "Url": f"{base}{m.group(1)}",
                        "Filename": m.group(1),
                    }
        return None

    def scrape_debian(self) -> Optional[Dict[str, Any]]:
        base = "https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/"
        html = self.dm.get_web_content(base)
        if html:
            m = re.search(r'href="(debian-live-(\d+\.\d+\.\d+)-amd64-xfce\.iso)"', html)
            if m:
                return {"Version": m.group(2), "Url": f"{base}{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_devuan(self) -> Optional[Dict[str, Any]]:
        for base in ["https://files.devuan.org/devuan_daedalus/installer-iso/", "https://pkgmaster.devuan.org/devuan_daedalus/installer-iso/"]:
            html = self.dm.get_web_content(base)
            if html:
                m = re.search(r'href="(devuan_daedalus_(\d+\.\d+\.\d+)_amd64_cd2\.iso)"', html)
                if m:
                    return {"Version": m.group(2), "Url": f"{base}{m.group(1)}", "Filename": m.group(1)}
                m2 = re.search(r'href="(devuan_daedalus_(\d+\.\d+\.\d+)_amd64_[^"]+\.iso)"', html)
                if m2:
                    return {"Version": m2.group(2), "Url": f"{base}{m2.group(1)}", "Filename": m2.group(1)}
        return None

    def scrape_fedora_workstation(self) -> Optional[Dict[str, Any]]:
        base = "https://ftp.halifax.rwth-aachen.de/fedora/linux/releases/"
        html = self.dm.get_web_content(base)
        if html:
            versions = re.findall(r'href="(\d+)/"', html)
            for v in sorted(versions, key=int, reverse=True)[:3]:
                sub = self.dm.get_web_content(f"{base}{v}/Workstation/x86_64/iso/")
                if sub:
                    m = re.search(r'href="(Fedora-Workstation-Live-[^"]+?\.iso)"', sub)
                    if m:
                        return {"Version": v, "Url": f"{base}{v}/Workstation/x86_64/iso/{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_gentoo_livegui(self) -> Optional[Dict[str, Any]]:
        base = "https://distfiles.gentoo.org/releases/amd64/autobuilds/current-livegui-amd64/"
        html = self.dm.get_web_content(base)
        if html:
            m = re.search(r'href="(livegui-amd64-(\d{8}T\d{6}Z)\.iso)"', html)
            if m:
                return {"Version": m.group(2), "Url": f"{base}{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_mageia(self) -> Optional[Dict[str, Any]]:
        for base in ["https://ftp.fau.de/mageia/iso/", "https://ftp.gwdg.de/pub/linux/mageia/iso/"]:
            html = self.dm.get_web_content(base)
            if html:
                versions = re.findall(r'href="(\d+)/"', html)
                for v in sorted(versions, key=int, reverse=True)[:3]:
                    sub = self.dm.get_web_content(f"{base}{v}/Mageia-{v}-x86_64/")
                    if sub:
                        m = re.search(r'href="(Mageia-[^"]+?\.iso)"', sub)
                        if m:
                            return {"Version": v, "Url": f"{base}{v}/Mageia-{v}-x86_64/{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_endeavouros(self) -> Optional[Dict[str, Any]]:
        for u in ["https://mirror.alpix.eu/endeavouros/iso/", "https://ftp.acc.umu.se/mirror/endeavouros/iso/"]:
            html = self.dm.get_web_content(u)
            if html:
                matches = re.findall(r'href="(EndeavourOS_[^"]*?-(\d{4}\.\d{2}\.\d{2})\.iso)"', html)
                if matches:
                    latest = sorted(matches, key=lambda x: x[1], reverse=True)[0]
                    return {"Version": latest[1], "Url": f"{u}{latest[0]}", "Filename": latest[0]}
        return None

    # --- 02 Enterprise Server ---
    def scrape_almalinux(self) -> Optional[Dict[str, Any]]:
        mirrors = [
            "https://ftp.halifax.rwth-aachen.de/almalinux/9/isos/x86_64/",
            "https://ftp.fau.de/almalinux/9/isos/x86_64/",
            "https://repo.almalinux.org/almalinux/9/isos/x86_64/",
        ]
        for base in mirrors:
            html = self.dm.get_web_content(base)
            if html:
                m = re.search(r'href=[\"\'](AlmaLinux-9[^\"]*?-x86_64-dvd\.iso)[\"\']', html)
                if m:
                    fn = m.group(1)
                    vm = re.search(r"AlmaLinux-9\.(\d+)", fn)
                    ver = f"9.{vm.group(1)}" if vm else "9"
                    return {"Version": ver, "Url": f"{base}{fn}", "Filename": fn}
        return None

    def scrape_centos_stream_9(self) -> Optional[Dict[str, Any]]:
        mirrors = [
            "https://ftp.halifax.rwth-aachen.de/centos-stream/9-stream/BaseOS/x86_64/iso/",
            "https://mirrors.almalinux.org/centos-stream/9-stream/BaseOS/x86_64/iso/",
            "https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/",
        ]
        for base in mirrors:
            html = self.dm.get_web_content(base)
            if html:
                m = re.search(r'href=[\"\'](CentOS-Stream-9[^\"]*?-x86_64-dvd1\.iso)[\"\']', html)
                if m:
                    fn = m.group(1)
                    vm = re.search(r"CentOS-Stream-9-(\d+)", fn)
                    ver = vm.group(1) if vm else "9"
                    return {"Version": ver, "Url": f"{base}{fn}", "Filename": fn}
        return None

    def scrape_proxmox_ve(self) -> Optional[Dict[str, Any]]:
        base = "https://enterprise.proxmox.com/iso/"
        html = self.dm.get_web_content(base)
        if html:
            m = re.search(r'href="\./(proxmox-ve_(\d+\.\d+-\d+)\.iso)"', html)
            if m:
                return {"Version": m.group(2), "Url": f"{base}{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_rocky_linux(self) -> Optional[Dict[str, Any]]:
        mirrors = [
            "https://ftp.halifax.rwth-aachen.de/rockylinux/9/isos/x86_64/",
            "https://ftp.fau.de/rockylinux/9/isos/x86_64/",
            "https://ftp.gwdg.de/pub/linux/rocky/9/isos/x86_64/",
            "https://download.rockylinux.org/pub/rocky/9/isos/x86_64/",
        ]
        for base in mirrors:
            html = self.dm.get_web_content(base)
            if html:
                m = re.search(r'href=[\"\'](Rocky-9[^\"]*?-x86_64-dvd\.iso)[\"\']', html)
                if m:
                    fn = m.group(1)
                    vm = re.search(r"Rocky-9\.(\d+)", fn)
                    ver = f"9.{vm.group(1)}" if vm else "9"
                    return {"Version": ver, "Url": f"{base}{fn}", "Filename": fn}
        return None

    def scrape_openmediavault(self) -> Optional[Dict[str, Any]]:
        js = self.dm.get_web_content("https://sourceforge.net/projects/openmediavault/best_release.json")
        if js:
            try:
                obj = json.loads(js)
                fn_path = obj.get("release", {}).get("filename", "")
                m = re.search(r"openmediavault_([0-9.]+[^/]*?)-amd64\.iso$", fn_path)
                if m:
                    fn = Path(fn_path).name
                    return {
                        "Version": m.group(1),
                        "Url": f"https://downloads.sourceforge.net/project/openmediavault{fn_path}",
                        "Filename": fn,
                    }
            except Exception:
                pass
        return {
            "Version": "8.3.1",
            "Url": "https://downloads.sourceforge.net/project/openmediavault/iso/8.3.1/openmediavault_8.3.1-amd64.iso",
            "Filename": "openmediavault_8.3.1-amd64.iso",
        }

    def scrape_zimaos(self) -> Optional[Dict[str, Any]]:
        api = self.dm.get_web_content("https://api.github.com/repos/IceWhaleTech/ZimaOS/releases/latest")
        if api:
            try:
                rel = json.loads(api)
                tag = rel["tag_name"].lstrip("v")
                for a in rel.get("assets", []):
                    if a.get("name", "").endswith(".iso"):
                        return {"Version": tag, "Url": a["browser_download_url"], "Filename": a["name"]}
            except Exception:
                pass
        return None

    def scrape_freenas_truenas(self) -> Optional[Dict[str, Any]]:
        html = self.dm.get_web_content("https://download.truenas.com/")
        if html:
            matches = re.findall(r'href="([^"]*?(TrueNAS-(?:SCALE|CORE)-(\d+\.\d+(\.\d+)*))\.iso)"', html)
            if matches:
                rel_url, _, ver, _ = matches[-1]
                fn = Path(rel_url).name
                return {"Version": ver, "Url": f"https://download.truenas.com/{rel_url}", "Filename": fn}
        return {
            "Version": "25.10.7",
            "Url": "https://download.truenas.com/TrueNAS-SCALE-Goldeye/25.10.7/TrueNAS-SCALE-25.10.7.iso",
            "Filename": "TrueNAS-SCALE-25.10.7.iso",
        }

    def scrape_ubuntu_server_lts(self) -> Optional[Dict[str, Any]]:
        base = "https://releases.ubuntu.com/"
        html = self.dm.get_web_content(base)
        if html:
            matches = [m[0] for m in re.findall(r'href="(\d+\.04(\.\d+)?)/"', html)]
            for v in sorted(matches, key=version_sort_key, reverse=True)[:3]:
                sub = self.dm.get_web_content(f"{base}{v}/")
                if sub:
                    m = re.search(r'href="(ubuntu-\d+\.04(\.\d+)?-live-server-amd64\.iso)"', sub)
                    if m:
                        return {"Version": v, "Url": f"{base}{v}/{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_rockstor(self) -> Optional[Dict[str, Any]]:
        html = self.dm.get_web_content("https://rockstor.com/dls/index.html")
        if html:
            m = re.search(r'href=["\']([^"\']*(Rockstor-Leap[0-9.]+-generic\.x86_64-([0-9.-]+)\.install\.iso))["\']', html)
            if m:
                return {"Version": m.group(3), "Url": m.group(1), "Filename": m.group(2)}
            m_gen = re.search(r'href=["\']([^"\']*(Rockstor-[^"\']*?-generic\.x86_64-([0-9.-]+)\.install\.iso))["\']', html)
            if m_gen:
                return {"Version": m_gen.group(3), "Url": m_gen.group(1), "Filename": m_gen.group(2)}
        return {
            "Version": "5.1.0-0",
            "Url": "https://rockstor.com/downloads/installer/leap/15.6/x86_64/Rockstor-Leap15.6-generic.x86_64-5.1.0-0.install.iso",
            "Filename": "Rockstor-Leap15.6-generic.x86_64-5.1.0-0.install.iso",
        }

    # --- 03 Security & Pentest ---
    def scrape_kali_linux(self) -> Optional[Dict[str, Any]]:
        mirrors = [
            "https://ftp.halifax.rwth-aachen.de/kali-images/current/",
            "https://cdimage.kali.org/current/",
        ]
        for base in mirrors:
            html = self.dm.get_web_content(base)
            if html:
                m = re.search(r'href=[\"\'](kali-linux-(\d{4}\.\d+)-installer-amd64\.iso)[\"\']', html)
                if m:
                    return {
                        "Version": m.group(2),
                        "Url": f"{base}{m.group(1)}",
                        "Filename": m.group(1),
                    }
        return None

    def scrape_blackarch_linux(self) -> Optional[Dict[str, Any]]:
        html = self.dm.get_web_content("https://ftp.halifax.rwth-aachen.de/blackarch/iso/")
        if html:
            m = re.search(r'href="(blackarch-linux-full-(\d{4}\.\d{2}\.\d{2})-x86_64\.iso)"', html)
            if m:
                return {
                    "Version": m.group(2),
                    "Url": f"https://ftp.halifax.rwth-aachen.de/blackarch/iso/{m.group(1)}",
                    "Filename": m.group(1),
                }
        return None

    def scrape_parrot_security(self) -> Optional[Dict[str, Any]]:
        for base in ["https://deb.parrot.sh/parrot/iso/", "https://download.parrot.sh/parrot/iso/"]:
            html = self.dm.get_web_content(base)
            if html:
                dirs = [m[0] for m in re.findall(r'href="(\d+\.\d+(\.\d+)?)/"', html)]
                for d in sorted(dirs, key=version_sort_key, reverse=True)[:3]:
                    sub = self.dm.get_web_content(f"{base}{d}/")
                    if sub:
                        m = re.search(r'href="(Parrot-security-[^"]*?amd64\.iso)"', sub)
                        if m:
                            return {"Version": d, "Url": f"{base}{d}/{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_caine_live_forensic__autopsy(self) -> Optional[Dict[str, Any]]:
        html = self.dm.get_web_content("https://www.caine-live.net/page5/page5.html")
        if html:
            m = re.search(r'href="https://www\.caine-live\.net/Downloads/(caine(\d+(\.\d+)?)\.iso)"', html)
            if m:
                fn = m.group(1)
                ver = m.group(2)
                return {
                    "Version": ver,
                    "Url": f"https://caine.mirror.garr.it/caine/{fn}",
                    "Filename": fn,
                    "ChecksumUrl": f"https://www.caine-live.net/page5/{fn}.sha256.txt",
                }
        return None

    # --- 04 Rescue Systeme ---
    def scrape_tiny_core_linux(self) -> Optional[Dict[str, Any]]:
        for base in ["http://tinycorelinux.net/16.x/x86_64/release/", "http://tinycorelinux.net/15.x/x86_64/release/"]:
            html = self.dm.get_web_content(base)
            if html:
                m = re.search(r'href="(CorePure64-(\d+\.\d+)\.iso)"', html)
                if m:
                    return {"Version": m.group(2), "Url": f"{base}{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_rescuezilla(self) -> Optional[Dict[str, Any]]:
        api = self.dm.get_web_content("https://api.github.com/repos/rescuezilla/rescuezilla/releases/latest")
        if api:
            try:
                rel = json.loads(api)
                tag = rel["tag_name"].lstrip("v")
                for a in rel.get("assets", []):
                    if a.get("name", "").endswith(".iso"):
                        return {"Version": tag, "Url": a["browser_download_url"], "Filename": a["name"]}
            except Exception:
                pass
        return None

    def scrape_gparted_live(self) -> Optional[Dict[str, Any]]:
        html = self.dm.get_web_content("https://gparted.org/download.php")
        if html:
            m = re.search(r'href="(https://[^"]*?gparted-live-(\d+\.\d+\.\d+-\d+)-amd64\.iso)"', html)
            if m:
                fn = f"gparted-live-{m.group(2)}-amd64.iso"
                return {"Version": m.group(2), "Url": m.group(1), "Filename": fn}
        return None

    def scrape_fygoos_pe(self) -> Optional[Dict[str, Any]]:
        html = self.dm.get_web_content("https://www.fygonas.com/download")
        if html:
            matches = re.findall(r'([^"\' ]*?fygoos_PE_x86[^"\' ]*?(\d+\.\d+[^"\' ]*)\.iso)', html)
            if matches:
                url, ver = matches[0]
                if url.startswith("//"):
                    url = "https:" + url
                elif not url.startswith("http"):
                    url = "https://www.fygonas.com" + url
                return {"Version": ver, "Url": url, "Filename": f"fygoos_PE_x86_{ver}.iso"}
        return {
            "Version": "1.2.0604_2686",
            "Url": "https://download.liveupdate.fygonas.com/x86_64/trim/fygoos_PE_x86_1.2.0604_2686.iso",
            "Filename": "fygoos_PE_x86_1.2.0604_2686.iso",
        }

    def scrape_netbootxyz(self) -> Optional[Dict[str, Any]]:
        api = self.dm.get_web_content("https://api.github.com/repos/netbootxyz/netboot.xyz/releases/latest")
        if api:
            try:
                rel = json.loads(api)
                tag = rel["tag_name"].lstrip("v")
                for a in rel.get("assets", []):
                    if a.get("name", "") == "netboot.xyz.iso":
                        return {"Version": tag, "Url": a["browser_download_url"], "Filename": "netboot.xyz.iso"}
            except Exception:
                pass
        return None

    def scrape_systemrescue_ehem_systemrescuecd(self) -> Optional[Dict[str, Any]]:
        html = self.dm.get_web_content("https://www.system-rescue.org/Download/")
        if html:
            m = re.search(r'(https://fastly-cdn\.system-rescue\.org/releases/(\d+\.\d+(\.\d+)?)/(systemrescue-\d+\.\d+(\.\d+)?-amd64\.iso))', html)
            if m:
                return {"Version": m.group(2), "Url": m.group(1), "Filename": m.group(4)}
            m2 = re.search(r"systemrescue-(\d+\.\d+(\.\d+)?)-amd64\.iso", html)
            if m2:
                ver = m2.group(1)
                fn = f"systemrescue-{ver}-amd64.iso"
                return {"Version": ver, "Url": f"https://fastly-cdn.system-rescue.org/releases/{ver}/{fn}", "Filename": fn}
        return None

    def scrape_rescatux(self) -> Optional[Dict[str, Any]]:
        js = self.dm.get_web_content("https://sourceforge.net/projects/rescatux/best_release.json")
        if js:
            try:
                obj = json.loads(js)
                fn_path = obj.get("release", {}).get("filename", "")
                m = re.search(r"rescatux-([0-9.]+)\.iso$", fn_path)
                if m:
                    fn = Path(fn_path).name
                    return {
                        "Version": m.group(1),
                        "Url": f"https://downloads.sourceforge.net/project/rescatux{fn_path}",
                        "Filename": fn,
                    }
            except Exception:
                pass
        return {
            "Version": "0.74",
            "Url": "https://downloads.sourceforge.net/project/rescatux/rescatux-0.74/rescatux-0.74.iso",
            "Filename": "rescatux-0.74.iso",
        }

    def scrape_kaspersky_rescue_disk(self) -> Optional[Dict[str, Any]]:
        return {
            "Version": "2024",
            "Url": "https://rescuedisk.s.kaspersky-labs.com/updatable/2024/krd.iso",
            "Filename": "krd.iso",
        }

    def scrape_eset_sysrescue_live(self) -> Optional[Dict[str, Any]]:
        return {
            "Version": "2024.05",
            "Url": "https://archive.org/download/eset_sysrescue_live_enu_202405/eset_sysrescue_live_enu.iso",
            "Filename": "eset_sysrescue_live_enu.iso",
        }

    def scrape_clonezilla_live(self) -> Optional[Dict[str, Any]]:
        chk = self.dm.get_web_content("https://clonezilla.org/downloads/stable/data/CHECKSUMS.TXT")
        if chk:
            m = re.search(r"clonezilla-live-(\d+\.\d+\.\d+-\d+)-amd64\.iso", chk)
            if m:
                fn = m.group(0)
                ver = m.group(1)
                url = f"https://downloads.sourceforge.net/project/clonezilla/clonezilla_live_stable/{ver}/{fn}"
                return {
                    "Version": ver,
                    "Url": url,
                    "Filename": fn,
                    "ChecksumUrl": "https://clonezilla.org/downloads/stable/data/CHECKSUMS.TXT",
                }
        return None

    def scrape_drweb_livedisk(self) -> Optional[Dict[str, Any]]:
        html = self.dm.get_web_content("https://free.drweb.com/livedisk/")
        if html:
            m = re.search(r"(https://cdn-download\.drweb\.com/pub/drweb/livedisk/(drweb-livedisk-(\d+)-cd\.iso))", html)
            if m:
                url = m.group(1)
                fn = m.group(2)
                ver = m.group(3)
                return {"Version": ver, "Url": url, "Filename": fn, "ChecksumUrl": f"{url}.md5"}
        return {
            "Version": "900",
            "Url": "https://cdn-download.drweb.com/pub/drweb/livedisk/drweb-livedisk-900-cd.iso",
            "Filename": "drweb-livedisk-900-cd.iso",
            "ChecksumUrl": "https://cdn-download.drweb.com/pub/drweb/livedisk/drweb-livedisk-900-cd.iso.md5",
        }

    def scrape_stresslinux(self) -> Optional[Dict[str, Any]]:
        ver = "0.7.106"
        fn = f"stresslinux_64bit_11.4.x86_64-{ver}.iso"
        url = f"https://downloads.sourceforge.net/project/archiveos/s/stresslinux/stresslinux_64bit_11.4.x86_64-{ver}.iso.bz2"
        return {"Version": ver, "Url": url, "Filename": f"{fn}.bz2", "ExtractTo": fn}

    # --- 05 BSD & Unix ---
    def scrape_freebsd(self) -> Optional[Dict[str, Any]]:
        base = "https://download.freebsd.org/releases/ISO-IMAGES/"
        html = self.dm.get_web_content(base)
        if html:
            matches = [m for m in re.findall(r'href="(\d+\.\d+)/"', html)]
            for v in sorted(matches, key=version_sort_key, reverse=True)[:3]:
                sub = self.dm.get_web_content(f"{base}{v}/")
                if sub:
                    m = re.search(r'href="(FreeBSD-[^"]*?-RELEASE-amd64-disc1\.iso)"', sub)
                    if m:
                        return {"Version": v, "Url": f"{base}{v}/{m.group(1)}", "Filename": m.group(1)}
        return None

    def scrape_openbsd(self) -> Optional[Dict[str, Any]]:
        base = "https://cdn.openbsd.org/pub/OpenBSD/"
        html = self.dm.get_web_content(base)
        if html:
            matches = re.findall(r'href="(\d+\.\d+)/"', html)
            for v in sorted(matches, key=version_sort_key, reverse=True)[:3]:
                sub = self.dm.get_web_content(f"{base}{v}/amd64/")
                if sub:
                    m = re.search(r"install(\d+)\.iso", sub)
                    if m:
                        fn = m.group(0)
                        return {
                            "Version": v,
                            "Url": f"{base}{v}/amd64/{fn}",
                            "Filename": fn,
                            "ChecksumUrl": f"{base}{v}/amd64/SHA256",
                        }
        return None

    def scrape_netbsd(self) -> Optional[Dict[str, Any]]:
        base = "https://cdn.netbsd.org/pub/NetBSD/images/"
        html = self.dm.get_web_content(base)
        if html:
            matches = [m[0] for m in re.findall(r'href="(\d+\.\d+(\.\d+)?)/"', html)]
            for v in sorted(matches, key=version_sort_key, reverse=True)[:3]:
                sub = self.dm.get_web_content(f"{base}{v}/")
                if sub:
                    m = re.search(rf"(NetBSD-{re.escape(v)}-amd64\.iso)", sub)
                    if m:
                        fn = m.group(1)
                        return {
                            "Version": v,
                            "Url": f"{base}{v}/{fn}",
                            "Filename": fn,
                            "ChecksumUrl": f"https://archive.netbsd.org/pub/NetBSD-archive/images/{v}/SHA512",
                        }
        return None

    def scrape_dragonfly_bsd(self) -> Optional[Dict[str, Any]]:
        base = "https://mirror.checkdomain.de/dragonflybsd/iso-images/"
        html = self.dm.get_web_content(base)
        if html:
            matches = re.findall(r'href="(dfly-x86_64-([\d\.]+)_REL\.iso)"', html)
            if matches:
                latest = sorted(matches, key=lambda x: version_sort_key(x[1]), reverse=True)[0]
                fn = latest[0]
                ver = latest[1]
                return {
                    "Version": ver,
                    "Url": f"{base}{fn}",
                    "Filename": fn,
                    "ChecksumUrl": f"{base}md5.txt",
                }
        return None


# ==============================================================================
# PRETTY ISO NAMES & THEMES
# ==============================================================================
def get_pretty_iso_name(filename: str) -> str:
    """Erzeugt formatierte Anzeigenamen für das Ventoy-Menü."""
    fn_lower = filename.lower()
    mapping = [
        ("clonezilla", "Clonezilla Live Disk Backup"),
        ("caine", "CAINE Live Digital Forensics & TSK"),
        ("drweb", "Dr.Web LiveDisk Antivirus"),
        ("stresslinux", "Stresslinux Hardware Load Test"),
        (r"openbsd|install\d+\.iso", "OpenBSD Release"),
        ("netbsd", "NetBSD Release"),
        (r"dfly|dragonfly", "DragonFly BSD Release"),
        ("alpine", "Alpine Linux Standard"),
        ("archlinux", "Arch Linux"),
        ("cachyos", "CachyOS Desktop Linux"),
        ("debian", "Debian GNU/Linux"),
        ("devuan", "Devuan GNU/Linux"),
        ("endeavouros", "EndeavourOS Linux"),
        ("fedora", "Fedora Workstation Live"),
        ("garuda", "Garuda Linux Dr460nized"),
        ("linuxmint", "Linux Mint Cinnamon"),
        (r"livegui.*gentoo", "Gentoo Live GUI"),
        ("mageia", "Mageia Linux"),
        ("omarchy", "Omarchy Linux"),
        ("ubuntucinnamon", "Ubuntu Cinnamon"),
        (r"ubuntu.*live-server", "Ubuntu Server LTS"),
        ("ubuntu", "Ubuntu Desktop"),
        ("zorin", "Zorin OS"),
        ("almalinux", "AlmaLinux Enterprise"),
        ("centos", "CentOS Stream"),
        ("openmediavault", "OpenMediaVault NAS"),
        ("zimaos", "ZimaOS Storage & Cloud"),
        (r"truenas|freenas", "FreeNAS / TrueNAS SCALE"),
        ("proxmox", "Proxmox VE Hypervisor"),
        ("rocky", "Rocky Linux"),
        ("rockstor", "Rockstor Btrfs NAS"),
        ("blackarch", "BlackArch Linux (Full)"),
        ("kali", "Kali Linux Security"),
        ("parrot", "Parrot Security OS"),
        ("corepure64", "Tiny Core Linux Pure64"),
        ("eset_sysrescue", "ESET SysRescue Live"),
        ("fygoos", "FygoOS PE Rescue"),
        ("gparted", "GParted Live Partition Editor"),
        ("krd", "Kaspersky Rescue Disk"),
        (r"netboot\.xyz", "netboot.xyz Multi-Boot"),
        (r"pts-desktop-live|phoronix", "Phoronix Test Suite Live"),
        ("rescatux", "Rescatux Boot & GRUB Repair"),
        ("rescuezilla", "Rescuezilla Recovery"),
        ("systemrescue", "SystemRescue (ehem. SystemRescueCd)"),
        ("freebsd", "FreeBSD Release"),
    ]
    for pattern, pretty in mapping:
        if re.search(pattern, fn_lower):
            return pretty

    clean = re.sub(r"\.iso$", "", filename, flags=re.IGNORECASE)
    clean = re.sub(r"[-_]", " ", clean)
    return clean.strip()


def get_ventoy_theme_definitions() -> Dict[str, Dict[str, str]]:
    """Gibt die 6 integrierten Ventoy-Themes zurück."""
    return {
        "1": {
            "key": "moderndark",
            "name": "Modern Dark",
            "desc": "Slate Blue & Cyan (Modern, aufgeräumt & kontrastreich)",
            "title": "VENTOY MULTIBOOT SYSTEM MANAGER",
            "title_color": "#38bdf8",
            "bg1": "#0f172a",
            "bg2": "#1e1e2e",
            "header": "#1e293b",
            "accent": "#38bdf8",
            "text": "#94a3b8",
            "sel_bg": "#38bdf8",
            "sel_fg": "#0f172a",
        },
        "2": {
            "key": "matrix",
            "name": "Matrix Hacker Terminal",
            "desc": "Nerdig, tiefes Schwarz & leuchtendes Terminal-Phosphorgrün",
            "title": "ROOT@TERMINAL // MULTIBOOT MATRIX",
            "title_color": "#22c55e",
            "bg1": "#050a05",
            "bg2": "#0a170d",
            "header": "#0f2314",
            "accent": "#22c55e",
            "text": "#86efac",
            "sel_bg": "#22c55e",
            "sel_fg": "#050a05",
        },
        "3": {
            "key": "cybertech",
            "name": "Cyber Tech & Network",
            "desc": "Technik & Netzwerk, Deep Navy & Electric Blue Infrastruktur",
            "title": "CYBER-NET // MULTIBOOT NETWORK OS SUITE",
            "title_color": "#38bdf8",
            "bg1": "#020817",
            "bg2": "#0c1e3d",
            "header": "#0f274c",
            "accent": "#3b82f6",
            "text": "#93c5fd",
            "sel_bg": "#3b82f6",
            "sel_fg": "#020817",
        },
        "4": {
            "key": "tuxamber",
            "name": "Tux Classic Linux",
            "desc": "Linux-Distro-Thema, Anthrazit-Carbon & warmes Tux-Gold",
            "title": "TUX MULTIBOOT // LINUX SYSTEM REPOSITORY",
            "title_color": "#f59e0b",
            "bg1": "#18181b",
            "bg2": "#27272a",
            "header": "#2e2e33",
            "accent": "#f59e0b",
            "text": "#fde68a",
            "sel_bg": "#f59e0b",
            "sel_fg": "#18181b",
        },
        "5": {
            "key": "crimson",
            "name": "Crimson Security & Audit",
            "desc": "Security & Pentest, Dark Carbon & Blood Crimson Red",
            "title": "CRIMSON SECURITY // RED TEAM AUDIT & RECOVERY",
            "title_color": "#ef4444",
            "bg1": "#0c0505",
            "bg2": "#1f0a0a",
            "header": "#2e0f0f",
            "accent": "#ef4444",
            "text": "#fca5a5",
            "sel_bg": "#ef4444",
            "sel_fg": "#0c0505",
        },
        "6": {
            "key": "synthwave",
            "name": "Synthwave Neon Retro",
            "desc": "80s Retro-Wave, Cyberpunk Midnight Purple & Hot Pink/Cyan",
            "title": "SYNTHWAVE MULTIBOOT // RETRO-WAVE",
            "title_color": "#f472b6",
            "bg1": "#13071f",
            "bg2": "#280b3d",
            "header": "#381054",
            "accent": "#ec4899",
            "text": "#e879f9",
            "sel_bg": "#ec4899",
            "sel_fg": "#13071f",
        },
    }


def hex_to_rgb(hex_code: str) -> Tuple[int, int, int]:
    h = hex_code.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


class VentoyThemeManager:
    """Generiert Pillow-Grafiken und richtet theme.txt sowie ventoy.json ein."""

    def __init__(self, logger: Logger):
        self.logger = logger
        self.themes = get_ventoy_theme_definitions()

    def get_theme_by_choice(self, choice: Optional[str]) -> Dict[str, str]:
        if not choice:
            return self.themes["1"]
        c = str(choice).strip().lower()
        if c in self.themes:
            return self.themes[c]
        for t in self.themes.values():
            if t["key"] == c:
                return t
        return self.themes["1"]

    def select_theme_interactive(self, default_choice: str = "1") -> str:
        print(f"\n{Colors.CYAN}{'=' * 60}{Colors.RESET}")
        print(f"{Colors.CYAN} VENTOY THEME AUSWAHL (6 Themen){Colors.RESET}")
        print(f"{Colors.CYAN}{'=' * 60}{Colors.RESET}")

        for k, t in sorted(self.themes.items()):
            def_marker = f" {Colors.GREEN}[Aktuell / Standard]{Colors.RESET}" if (k == default_choice or t["key"] == default_choice) else ""
            print(f" {Colors.YELLOW}[{k}]{Colors.RESET} {Colors.WHITE}{t['name']}{Colors.RESET}{def_marker}")
            print(f"     {Colors.DARK_GRAY}{t['desc']}{Colors.RESET}")

        print("")
        try:
            choice = input(f"Bitte Nummer des Ventoy-Themes eingeben (1-6) [Standard: {default_choice}]: ").strip()
        except (KeyboardInterrupt, EOFError):
            print("")
            return default_choice

        if not choice:
            choice = default_choice
        for k, t in self.themes.items():
            if t["key"] == choice.lower():
                return k
        if choice not in self.themes:
            choice = "1"
        return choice

    def install_theme(self, ventoy_dir: Path, theme_choice: str = "1", force: bool = False, dry_run: bool = False) -> None:
        selected = self.get_theme_by_choice(theme_choice)

        if dry_run:
            self.logger.log(
                f"[DRY-RUN] Würde Ventoy-Theme '{selected['name']}' (1080p) auf '{ventoy_dir}' einrichten.",
                color=Colors.CYAN,
                level="INFO",
            )
            return

        theme_dir = ventoy_dir / "theme"
        bg_path = theme_dir / "background.png"
        sel_path = theme_dir / "select_c.png"
        theme_txt_path = theme_dir / "theme.txt"
        active_record_path = ventoy_dir / "theme_active.txt"

        if not force and active_record_path.exists():
            try:
                existing = active_record_path.read_text(encoding="utf-8").strip()
                if existing == selected["key"] and bg_path.exists() and sel_path.exists() and theme_txt_path.exists():
                    self.logger.log(
                        f"[VENTOY] Theme '{selected['name']}' ist bereits aktiv auf Ziel-Laufwerk.",
                        color=Colors.GREEN,
                        level="OK",
                    )
                    return
            except Exception:
                pass

        theme_dir.mkdir(parents=True, exist_ok=True)

        try:
            # 1. 1080p Hintergrund generieren (1920x1080)
            w, h = 1920, 1080
            c1 = hex_to_rgb(selected["bg1"])
            c2 = hex_to_rgb(selected["bg2"])

            grad_small = Image.new("RGB", (256, 144))
            pixels = grad_small.load()
            for y in range(144):
                for x in range(256):
                    factor = (x / 256.0 + y / 144.0) / 2.0
                    r = int(c1[0] + factor * (c2[0] - c1[0]))
                    g = int(c1[1] + factor * (c2[1] - c1[1]))
                    b = int(c1[2] + factor * (c2[2] - c1[2]))
                    pixels[x, y] = (r, g, b)

            img = grad_small.resize((w, h), Image.Resampling.BICUBIC)
            draw = ImageDraw.Draw(img)

            header_color = hex_to_rgb(selected["header"])
            draw.rectangle([0, 0, w, 80], fill=header_color)
            draw.rectangle([0, 1020, w, h], fill=header_color)

            accent_color = hex_to_rgb(selected["accent"])
            draw.line([(0, 80), (w, 80)], fill=accent_color, width=3)
            draw.line([(0, 1020), (w, 1020)], fill=accent_color, width=3)

            subtle_color = (accent_color[0] // 4, accent_color[1] // 4, accent_color[2] // 4)
            draw.line([(0, 84), (w, 84)], fill=subtle_color, width=1)
            draw.line([(0, 1016), (w, 1016)], fill=subtle_color, width=1)

            img.save(bg_path, format="PNG")

            # 2. Auswahlelement (select_c.png, 32x36)
            sel_img = Image.new("RGB", (32, 36), color=hex_to_rgb(selected["sel_bg"]))
            sel_img.save(sel_path, format="PNG")
        except Exception as e:
            self.logger.log(f"[VENTOY] Warnung beim Erstellen der Theme-Grafiken: {e}", color=Colors.YELLOW, level="WARNUNG")

        # 3. theme.txt schreiben
        theme_txt_content = f"""# Ventoy Theme: {selected['name']}
desktop-image: "background.png"
desktop-color: "{selected['bg1']}"
title-text: "{selected['title']}"
title-color: "{selected['title_color']}"
message-color: "{selected['text']}"

+ boot_menu {{
    left = 10%
    top = 12%
    width = 80%
    height = 78%
    item_color = "{selected['text']}"
    selected_item_color = "{selected['sel_fg']}"
    selected_item_pixmap_style = "select_*.png"
    item_icon_space = 24
    item_height = 36
    item_padding = 10
    item_spacing = 4
}}

+ label {{
    left = 0%
    top = 95%
    width = 100%
    height = 30
    text = "[F1] Memdisk  |  [F2] Power  |  [F3] ListView/TreeView  |  [F4] Localboot  |  [F5] Tools"
    color = "{selected['text']}"
    align = "center"
}}
"""
        try:
            theme_txt_path.write_text(theme_txt_content, encoding="utf-8")
            active_record_path.write_text(selected["key"], encoding="utf-8")
            self.logger.log(f"[VENTOY] Theme '{selected['name']}' (1080p) auf Ziel-Laufwerk eingerichtet.", color=Colors.GREEN, level="ERFOLG")
        except Exception as e:
            self.logger.log(f"[VENTOY] Fehler beim Schreiben von theme.txt ({theme_txt_path}): {e}", color=Colors.RED, level="FEHLER")


# ==============================================================================
# VENTOY LAUFWERKS-ERKENNUNG & INSTALLER (LINUX CLI)
# ==============================================================================
class VentoyLinuxDriveManager:
    """Verwaltet Wechseldatenträger, Mountpoints und CLI-Installationen."""

    def __init__(self, logger: Logger):
        self.logger = logger

    def get_mounted_drives(self) -> List[Dict[str, Any]]:
        """Ermittelt alle unter Linux gemounteten Wechseldatenträger und Ventoy-Laufwerke."""
        drives = []
        try:
            res = subprocess.run(
                ["lsblk", "-J", "-o", "NAME,TYPE,SIZE,MOUNTPOINT,LABEL,RM,HOTPLUG,FSTYPE,MODEL,TRAN"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            if res.returncode == 0:
                data = json.loads(res.stdout)
                for dev in data.get("blockdevices", []):
                    self._parse_lsblk_node(dev, drives)
        except Exception:
            pass

        # Zusätzliche Prüfung gängiger Mountpoints unter /media und /run/media
        seen_mounts = {d["mountpoint"] for d in drives}
        user = os.environ.get("USER", "")
        scan_paths = [Path("/media"), Path(f"/run/media/{user}"), Path("/mnt")]

        for base_p in scan_paths:
            if base_p.exists() and base_p.is_dir():
                for sub in base_p.iterdir():
                    if sub.is_dir() and str(sub) not in seen_mounts:
                        try:
                            usage = shutil.disk_usage(sub)
                            drives.append(
                                {
                                    "name": sub.name,
                                    "mountpoint": str(sub),
                                    "label": sub.name,
                                    "fstype": "unknown",
                                    "free_gb": usage.free / (1024**3),
                                    "total_gb": usage.total / (1024**3),
                                    "is_removable": True,
                                    "is_ventoy": (sub / "ventoy").exists() or "ventoy" in sub.name.lower(),
                                }
                            )
                            seen_mounts.add(str(sub))
                        except Exception:
                            pass
        return drives

    def _parse_lsblk_node(self, node: Dict[str, Any], results: List[Dict[str, Any]]) -> None:
        mount = node.get("mountpoint")
        if mount and mount not in ["/", "/boot", "/boot/efi", "/home", "[SWAP]"]:
            label = node.get("label") or ""
            is_ventoy = "ventoy" in label.lower() or Path(f"{mount}/ventoy").exists()
            is_removable = bool(node.get("rm") or node.get("hotplug") or node.get("tran") == "usb")

            try:
                usage = shutil.disk_usage(mount)
                results.append(
                    {
                        "name": node.get("name"),
                        "mountpoint": mount,
                        "label": label,
                        "fstype": node.get("fstype", ""),
                        "free_gb": usage.free / (1024**3),
                        "total_gb": usage.total / (1024**3),
                        "is_removable": is_removable,
                        "is_ventoy": is_ventoy,
                    }
                )
            except Exception:
                pass

        for child in node.get("children", []):
            self._parse_lsblk_node(child, results)

    def select_target_mount_interactive(self, total_gb_needed: float) -> Optional[str]:
        drives = self.get_mounted_drives()
        if not drives:
            self.logger.log("Keine passenden Ziel-Laufwerke gefunden! Bitte --target <pfad> angeben.", color=Colors.RED, level="FEHLER")
            return None

        print(f"\n{Colors.CYAN}{'=' * 60}{Colors.RESET}")
        print(f"{Colors.CYAN} VENTOY ZIEL-LAUFWERK AUSWAHL{Colors.RESET}")
        print(f"{Colors.CYAN}{'=' * 60}{Colors.RESET}")
        print(f"{Colors.YELLOW} Benötigter Speicherplatz: ca. {total_gb_needed:.2f} GB{Colors.RESET}\n")

        for idx, d in enumerate(drives, 1):
            status = f"{Colors.GREEN}--> [GENUG PLATZ]{Colors.RESET}" if d["free_gb"] >= total_gb_needed else f"{Colors.RED}--> [ZU WENIG PLATZ - fehlen ca. {total_gb_needed - d['free_gb']:.2f} GB]{Colors.RESET}"
            marker = f" {Colors.GREEN}[Ventoy]{Colors.RESET}" if d["is_ventoy"] else ""
            print(f" [{idx}] {d['mountpoint']} [{d['label']}] ({d['free_gb']:.2f} GB frei / {d['total_gb']:.2f} GB Gesamt, {d['fstype']}){marker} {status}")

        print("")
        try:
            sel = input(f"Bitte Nummer des Ventoy-Ziel-Laufwerks eingeben (1-{len(drives)}): ").strip()
            if sel.isdigit() and 1 <= int(sel) <= len(drives):
                return drives[int(sel) - 1]["mountpoint"]
        except (KeyboardInterrupt, EOFError):
            print("")
            return None
        return None

    def install_ventoy_cli(self, tools_dir: Path, target_device: Optional[str] = None, dry_run: bool = False) -> None:
        """Lädt Ventoy für Linux herunter und installiert oder aktualisiert es auf einem USB-Blockgerät."""
        print(f"\n{Colors.CYAN}{'=' * 60}{Colors.RESET}")
        print(f"{Colors.CYAN} AUTOMATISIERTE VENTOY-INSTALLATION (CLI LINUX){Colors.RESET}")
        print(f"{Colors.CYAN}{'=' * 60}{Colors.RESET}")

        # 1. Ventoy Tarball von GitHub Releases beschaffen
        ventoy_script = self._ensure_ventoy_linux_package(tools_dir)
        if not ventoy_script or not ventoy_script.exists():
            self.logger.log("Konnte Ventoy2Disk.sh nicht beschaffen. Abbruch.", color=Colors.RED, level="FEHLER")
            return

        # 2. Blockgeräte via lsblk listen
        if not target_device:
            res = subprocess.run(
                ["lsblk", "-d", "-o", "NAME,SIZE,MODEL,TRAN,RM,RO"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            print(f"\n{Colors.YELLOW}Verfügbare physische Laufwerke:{Colors.RESET}")
            lines = res.stdout.strip().splitlines()
            devices = []
            for line in lines[1:]:
                parts = line.split()
                if not parts:
                    continue
                dev_name = parts[0]
                if dev_name.startswith("loop") or dev_name.startswith("ram"):
                    continue
                devices.append(f"/dev/{dev_name}")
                print(f" [{len(devices)}] /dev/{dev_name}  {line}")

            if not devices:
                self.logger.log("Keine geeigneten Blockgeräte gefunden.", color=Colors.RED, level="FEHLER")
                return

            try:
                sel = input(f"\nBitte Nummer des USB-Laufwerks für Ventoy eingeben (1-{len(devices)}): ").strip()
                if not sel.isdigit() or not (1 <= int(sel) <= len(devices)):
                    self.logger.log("Ungültige Auswahl. Abbruch.", color=Colors.RED, level="FEHLER")
                    return
                target_device = devices[int(sel) - 1]
            except (KeyboardInterrupt, EOFError):
                print("")
                return

        # 3. Prüfen ob Ventoy bereits vorhanden ist
        is_ventoy = False
        try:
            blkid_res = subprocess.run(["blkid", target_device], stdout=subprocess.PIPE, text=True)
            if "ventoy" in blkid_res.stdout.lower():
                is_ventoy = True
        except Exception:
            pass

        flag = "-i"
        if is_ventoy:
            print(f"\n{Colors.YELLOW}[HINWEIS] Auf {target_device} scheint bereits Ventoy installiert zu sein!{Colors.RESET}")
            print(" [1] Neuinstallation (-i: Formatieren, ALLE DATEN LÖSCHEN)")
            print(" [2] Aktualisierung (-u: Zerstörungsfreies Bootcode-Update, Daten bleiben erhalten)")
            print(" [3] Abbrechen")
            ans = input("Wähle eine Option (1, 2 oder 3): ").strip()
            if ans == "2":
                flag = "-u"
            elif ans == "1":
                flag = "-i"
            else:
                self.logger.log("Installation abgebrochen.", color=Colors.YELLOW, level="ABBRUCH")
                return

        if flag == "-i":
            print(f"\n{Colors.RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!{Colors.RESET}")
            print(f"{Colors.RED} WARNUNG: Alle vorhandenen Daten auf {target_device} werden UNWIDERRUFLICH GELÖSCHT!{Colors.RESET}")
            print(f"{Colors.RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!{Colors.RESET}")
            confirm = input(f"Bist du VOLLKOMMEN SICHER, dass du Ventoy auf {target_device} installieren willst? (j/N): ").strip().lower()
            if confirm not in ["j", "ja", "y", "yes"]:
                self.logger.log("Installation aus Sicherheitsgründen abgebrochen.", color=Colors.YELLOW, level="ABBRUCH")
                return

        cmd = [str(ventoy_script), flag, target_device]
        if os.geteuid() != 0:
            cmd = ["sudo"] + cmd

        if dry_run:
            self.logger.log(f"[DRY-RUN] Würde ausführen: {' '.join(cmd)}", color=Colors.DARK_GRAY, level="DRY-RUN")
            return

        self.logger.log(f"Starte Ventoy Installation ({flag}) auf {target_device}...", color=Colors.CYAN, level="VENTOY")
        try:
            subprocess.run(cmd, check=True)
            self.logger.log(f"Ventoy wurde ERFOLGREICH auf {target_device} eingerichtet!", color=Colors.GREEN, level="ERFOLG")
        except Exception as e:
            self.logger.log(f"Fehler bei Ventoy-Installation: {e}", color=Colors.RED, level="FEHLER")

    def _ensure_ventoy_linux_package(self, tools_dir: Path) -> Optional[Path]:
        """Sucht Ventoy2Disk.sh oder lädt das offizielle GitHub Release-Tarball herunter."""
        tools_dir.mkdir(parents=True, exist_ok=True)

        for p in tools_dir.glob("**/Ventoy2Disk.sh"):
            if p.is_file():
                os.chmod(p, 0o755)
                return p

        self.logger.log("Lade offizielles Ventoy Linux-Paket von GitHub Releases...", color=Colors.CYAN, level="VENTOY")
        try:
            resp = requests.get(
                "https://api.github.com/repos/ventoy/Ventoy/releases/latest",
                headers={"User-Agent": "Linux-ISO-Updater"},
                timeout=15,
            )
            if resp.status_code == 200:
                data = resp.json()
                for asset in data.get("assets", []):
                    name = asset.get("name", "")
                    if re.match(r"^ventoy-.*-linux\.tar\.gz$", name):
                        tar_url = asset["browser_download_url"]
                        tar_file = tools_dir / name
                        self.logger.log(f"Download: {tar_url}...", color=Colors.CYAN, level="VENTOY")
                        with requests.get(tar_url, stream=True, timeout=30) as r:
                            r.raise_for_status()
                            with open(tar_file, "wb") as f:
                                shutil.copyfileobj(r.raw, f)

                        self.logger.log(f"Entpacke Ventoy nach {tools_dir}...", color=Colors.CYAN, level="VENTOY")
                        subprocess.run(["tar", "-xzf", str(tar_file), "-C", str(tools_dir)], check=True)
                        tar_file.unlink(missing_ok=True)

                        for p in tools_dir.glob("**/Ventoy2Disk.sh"):
                            if p.is_file():
                                os.chmod(p, 0o755)
                                return p
        except Exception as e:
            self.logger.log(f"Automatischer Ventoy-Download fehlgeschlagen: {e}", color=Colors.RED, level="FEHLER")
        return None


# ==============================================================================
# INTERAKTIVE DISTRIBUTIONS-AUSWAHL
# ==============================================================================
def select_distros_interactive(distros_list: List[Dict[str, Any]], iso_dir: Path, logger: Logger) -> None:
    """Interaktiver Start-Dialog zur Auswahl gewünschter Distributionen."""
    group_map: Dict[int, Dict[str, Any]] = {}
    ordered_list: List[Dict[str, Any]] = []
    group_idx = 1

    for cat in CATEGORY_ORDER:
        in_cat = sorted([d for d in distros_list if d.get("Category") == cat], key=lambda x: x.get("Name", "").lower())
        if in_cat:
            group_map[group_idx] = {"Category": cat, "Items": in_cat}
            ordered_list.extend(in_cat)
            group_idx += 1

    leftovers = sorted([d for d in distros_list if d.get("Category") not in CATEGORY_ORDER], key=lambda x: x.get("Name", "").lower())
    if leftovers:
        group_map[group_idx] = {"Category": "Sonstige", "Items": leftovers}
        ordered_list.extend(leftovers)

    # Vorab alle vorhandenen lokalen ISOs im Verzeichnis erfassen
    existing_isos = [
        p
        for p in iso_dir.rglob("*.iso")
        if "Archiv" not in p.parts and not p.name.endswith(".part") and p.is_file() and p.stat().st_size > 1024 * 1024
    ]

    cols = shutil.get_terminal_size(fallback=(80, 24)).columns
    border_len = min(90, max(40, cols - 1))
    banner_border = "=" * border_len
    sub_border = "-" * border_len

    print("")
    print(f"{Colors.CYAN}{banner_border}{Colors.RESET}")
    print(f"{Colors.YELLOW}{'DISTRIBUTIONS-AUSWAHL (MEHRFACHWAHL)'.center(border_len)}{Colors.RESET}")
    print(f"{Colors.CYAN}{banner_border}{Colors.RESET}")
    print(f"{Colors.WHITE}Wähle aus, welche Distributionen künftig geprüft, geladen und synchronisiert werden:{Colors.RESET}")
    print(f"{Colors.DARK_GRAY}Legende: {Colors.GREEN}[x]{Colors.DARK_GRAY} = ISO bereits lokal vorhanden | {Colors.WHITE}[ ]{Colors.DARK_GRAY} = Noch nicht heruntergeladen{Colors.RESET}")
    print(f"{Colors.DARK_GRAY}Eingabeformate: 'all' (alle), Gruppen z.B. 'G1, G4' oder Nummern z.B. '1, 3, 5-8'!{Colors.RESET}")
    print(f"{Colors.DARK_GRAY}{sub_border}{Colors.RESET}")

    num_index = 1
    index_item_map: Dict[int, Dict[str, Any]] = {}

    for g_id in sorted(group_map.keys()):
        g = group_map[g_id]
        print(f"\n {Colors.CYAN}[Gruppe G{g_id}] {g['Category']}{Colors.RESET}")
        print(f" {Colors.DARK_GRAY}{'-' * min(88, max(38, cols - 3))}{Colors.RESET}")
        for d in g["Items"]:
            index_item_map[num_index] = d

            pat = d.get("MatchPattern")
            local_match = None
            if pat:
                for p in existing_isos:
                    if re.search(pat, p.name):
                        local_match = p
                        break

            is_present = local_match is not None
            status_str = f"{Colors.GREEN}[x]{Colors.RESET}" if is_present else f"{Colors.DARK_GRAY}[ ]{Colors.RESET}"

            if is_present:
                size_mb = int(round(local_match.stat().st_size / (1024 * 1024), 0))
                size_str = f"{size_mb} MB vorhanden"
            else:
                size_bytes = d.get("SizeBytes", 0)
                size_mb = int(round(size_bytes / (1024 * 1024), 0)) if size_bytes else 0
                size_str = f"ca. {size_mb} MB Download" if size_mb > 0 else "Größe unbekannt"

            print(f"   {num_index:2d}) {status_str} {d.get('Name', ''):<32} ({size_str})")
            num_index += 1

    print("")
    print(f"{Colors.DARK_GRAY}{sub_border}{Colors.RESET}")
    print(f"{Colors.YELLOW}Auswahl eingeben (ENTER = alle Distros auswählen):{Colors.RESET}")
    try:
        raw_input = input("Auswahl (z.B. all / G1, G3 / 1,4,7-10) [ENTER = all]: ").strip()
    except (KeyboardInterrupt, EOFError):
        print("")
        raw_input = "all"

    if not raw_input:
        raw_input = "all"

    selected_names = set()
    if raw_input.lower() in ["all", "*"]:
        selected_names = {d["Name"] for d in ordered_list}
    else:
        tokens = re.split(r"[,; ]+", raw_input)
        for tok in tokens:
            t = tok.strip()
            if not t:
                continue
            mg = re.match(r"^[gG](\d+)$", t)
            mr = re.match(r"^(\d+)-(\d+)$", t)
            if mg:
                gid = int(mg.group(1))
                if gid in group_map:
                    for d in group_map[gid]["Items"]:
                        selected_names.add(d["Name"])
            elif mr:
                start, end = int(mr.group(1)), int(mr.group(2))
                for n in range(start, end + 1):
                    if n in index_item_map:
                        selected_names.add(index_item_map[n]["Name"])
            elif t.isdigit():
                n = int(t)
                if n in index_item_map:
                    selected_names.add(index_item_map[n]["Name"])

    deselected_with_files = []
    for d in ordered_list:
        was_enabled = d.get("Enabled", True)
        is_now_enabled = d["Name"] in selected_names
        d["Enabled"] = is_now_enabled

        # Wenn abgewählt, prüfen ob lokale ISOs existieren
        if was_enabled and not is_now_enabled:
            pattern = d.get("MatchPattern")
            if pattern:
                local_matches = []
                for p in iso_dir.rglob("*.iso"):
                    if "Archiv" not in str(p) and re.search(pattern, p.name):
                        local_matches.append(p)
                if local_matches:
                    deselected_with_files.append({"Name": d["Name"], "Files": local_matches})

    active_count = sum(1 for d in ordered_list if d.get("Enabled", True))
    print(f"\n{Colors.GREEN}[INFO] Es wurden {active_count} von {len(ordered_list)} Distributionen aktiviert.{Colors.RESET}\n")

    # Nachfrage zum Löschen abgewählter ISOs
    if deselected_with_files:
        print(f"{Colors.YELLOW}[ABGEWÄHLTE LOKALE DATEIEN GEFUNDEN]{Colors.RESET}")
        print("Für folgende abgewählte Distributionen existieren noch lokale ISO-Dateien:")
        for des in deselected_with_files:
            for f in des["Files"]:
                size_mb = f.stat().st_size / (1024 * 1024)
                print(f" - {des['Name']}: {f.name} ({size_mb:.2f} MB)")
        print("")
        try:
            del_ans = input("Möchtest du diese nicht mehr ausgewählten ISOs jetzt löschen? (j/N): ").strip().lower()
            if del_ans in ["j", "ja", "y", "yes"]:
                for des in deselected_with_files:
                    for f in des["Files"]:
                        try:
                            f.unlink()
                            print(f"{Colors.GREEN}   [GELÖSCHT] {f.name}{Colors.RESET}")
                        except Exception as e:
                            print(f"{Colors.RED}   [FEHLER] Konnte {f.name} nicht löschen: {e}{Colors.RESET}")
            else:
                print(f"{Colors.DARK_GRAY}   [BEIBEHALTEN] Lokale Dateien werden behalten, aber künftig nicht mehr synchronisiert.{Colors.RESET}")
        except (KeyboardInterrupt, EOFError):
            print("")


# ==============================================================================
# VENTOY KOPIERVORGANG & MENÜ-SYNCHRONISIERUNG
# ==============================================================================
def copy_file_with_progress(src_path: Path, dst_path: Path) -> None:
    """Kopiert eine Datei mit In-Place Terminal-Fortschrittsanzeige."""
    total_bytes = src_path.stat().st_size
    dst_path.parent.mkdir(parents=True, exist_ok=True)

    buffer_size = 1024 * 1024  # 1 MB Puffer
    start_time = time.monotonic()
    last_report = 0.0
    total_read = 0
    is_tty = sys.stdout.isatty()
    report_interval = 0.1 if is_tty else 5.0

    with open(src_path, "rb") as fsrc, open(dst_path, "wb") as fdst:
        while chunk := fsrc.read(buffer_size):
            fdst.write(chunk)
            total_read += len(chunk)

            now = time.monotonic()
            if now - last_report >= report_interval or total_read == total_bytes:
                elapsed = max(now - start_time, 0.001)
                speed_bytes_sec = total_read / elapsed
                status = format_progress_bar("   [KOPIERE]", total_read, total_bytes, speed_bytes_sec)

                if is_tty:
                    sys.stdout.write(f"\r\033[K{Colors.CYAN}{status}{Colors.RESET}")
                    sys.stdout.flush()
                else:
                    sys.stdout.write(f"{status}\n")
                    sys.stdout.flush()
                last_report = now

    if is_tty:
        sys.stdout.write("\n")
        sys.stdout.flush()


def run_ventoy_sync(
    target_drive: str,
    source_dir: Path,
    distro_patterns: List[Dict[str, Any]],
    theme_choice: Optional[str],
    dry_run: bool,
    logger: Logger,
) -> None:
    """Synchronisiert ISOs auf das Ventoy-Laufwerk, bereinigt Altbestände und schreibt die Konfiguration."""
    target_root = Path(target_drive).resolve()
    if not target_root.exists():
        logger.log(f"Ziel-Laufwerk {target_root} existiert nicht oder ist nicht bereit!", color=Colors.RED, level="FEHLER")
        return

    # Kategorien ermitteln
    category_folders = [p for p in source_dir.iterdir() if p.is_dir() and not p.name.startswith((".", "Archiv", "scratch", "tools"))]

    iso_files_to_copy = []
    for folder in category_folders:
        for iso in folder.rglob("*.iso"):
            # Prüfen ob Distro aktiviert ist
            is_enabled = True
            for d in distro_patterns:
                pat = d.get("MatchPattern")
                if pat and re.search(pat, iso.name):
                    if d.get("Enabled") is False:
                        is_enabled = False
                    break
            if not is_enabled:
                continue

            rel_path = iso.relative_to(source_dir)
            size_bytes = iso.stat().st_size
            iso_files_to_copy.append(
                {
                    "source": iso,
                    "rel_path": rel_path,
                    "category": folder.name,
                    "filename": iso.name,
                    "size_bytes": size_bytes,
                    "size_mb": size_bytes / (1024 * 1024),
                }
            )

    if not iso_files_to_copy:
        logger.log("Keine aktivierten ISO-Dateien zum Kopieren im Quellverzeichnis gefunden.", color=Colors.YELLOW, level="WARNUNG")
        return

    # Netto-Speicherbedarf berechnen
    actual_bytes_needed = 0
    already_present_count = 0
    need_copy_count = 0

    for item in iso_files_to_copy:
        dst_iso = target_root / item["category"] / item["filename"]
        if dst_iso.exists() and dst_iso.stat().st_size == item["size_bytes"]:
            already_present_count += 1
        else:
            actual_bytes_needed += item["size_bytes"]
            need_copy_count += 1

    usage = shutil.disk_usage(target_root)
    free_gb = usage.free / (1024**3)
    needed_gb = actual_bytes_needed / (1024**3)
    total_all_gb = sum(item["size_bytes"] for item in iso_files_to_copy) / (1024**3)

    logger.log(f"Ventoy-Kopiervorgang vorbereiten nach: {target_root}", color=Colors.CYAN, level="VENTOY")
    logger.log(
        f"Gefundene ISO-Dateien: {len(iso_files_to_copy)} Dateien in {len(category_folders)} Ordnern (Gesamt: {total_all_gb:.2f} GB)",
        color=Colors.GREEN,
        level="INFO",
    )
    logger.log(
        f"Bereits auf Ziel vorhanden: {already_present_count} ISOs | Neu zu kopieren: {need_copy_count} ISOs ({needed_gb:.2f} GB)",
        color=Colors.DARK_GRAY,
        level="INFO",
    )
    logger.log(f"Freier Speicherplatz auf {target_root}: {free_gb:.2f} GB", color=Colors.DARK_GRAY, level="INFO")

    # Speicherprüfung
    if usage.free < actual_bytes_needed:
        shortage_gb = (actual_bytes_needed - usage.free) / (1024**3)
        print("")
        logger.log("=" * 60, color=Colors.RED, level="FEHLER")
        logger.log(f"[SPEICHERPLATZ-FEHLER] Nicht genügend freier Speicherplatz auf Ziel-Laufwerk {target_root}!", color=Colors.RED, level="FEHLER")
        logger.log(f"  Benötigt für neue/geänderte ISOs: {needed_gb:.2f} GB", color=Colors.YELLOW, level="FEHLER")
        logger.log(f"  Freier Speicherplatz verfügbar:      {free_gb:.2f} GB", color=Colors.YELLOW, level="FEHLER")
        logger.log(f"  Fehlender Speicherplatz:              {shortage_gb:.2f} GB", color=Colors.RED, level="FEHLER")
        logger.log("=" * 60, color=Colors.RED, level="FEHLER")
        print("")

        if dry_run:
            logger.log("[DRY-RUN] Speicherplatz reicht nicht aus. Im Echtlauf würde der Kopiervorgang fehlschlagen.", color=Colors.YELLOW, level="DRY-RUN")
        else:
            abort = input("Möchtest du den Kopiervorgang jetzt abbrechen? (J/n): ").strip().lower()
            if abort not in ["n", "no", "nein"]:
                logger.log("Kopiervorgang durch Benutzer wegen unzureichendem Speicherplatz abgebrochen.", color=Colors.YELLOW, level="ABBRUCH")
                return
            logger.log("Kopiervorgang wird auf ausdrücklichen Wunsch fortgesetzt...", color=Colors.YELLOW, level="WARNUNG")

    # Bereinigung abgewählter ISOs auf dem Ziel-Stick
    deselected = [d for d in distro_patterns if d.get("Enabled") is False and d.get("MatchPattern")]
    for des in deselected:
        pat = des["MatchPattern"]
        for target_iso in target_root.rglob("*.iso"):
            if re.search(pat, target_iso.name):
                mb = target_iso.stat().st_size / (1024 * 1024)
                if dry_run:
                    logger.log(f"[DRY-RUN] Abgewählte ISO auf Ventoy-Ziel würde gelöscht: {target_iso.name} ({mb:.2f} MB)", color=Colors.YELLOW, level="CLEANUP")
                else:
                    logger.log(f"[CLEANUP] Abgewählte ISO auf Ventoy-Ziel ENDGÜLTIG gelöscht: {target_iso.name} ({mb:.2f} MB)", color=Colors.YELLOW, level="CLEANUP")
                    try:
                        target_iso.unlink()
                    except Exception:
                        pass

    # Kopiervorgang durchführen
    total_copy = len(iso_files_to_copy)
    current_copy = 0

    for item in iso_files_to_copy:
        current_copy += 1
        dst_cat_dir = target_root / item["category"]
        dst_iso = dst_cat_dir / item["filename"]

        if dry_run:
            logger.log(
                f"[DRY-RUN] [{current_copy}/{total_copy}] Würde kopieren: {item['filename']} ({item['size_mb']:.2f} MB) -> {dst_iso}",
                color=Colors.DARK_GRAY,
                level="DRY-RUN",
            )
            continue

        logger.clear_screen_ventoy_copy(current_copy, total_copy, item["filename"], item["size_mb"])
        logger.log(f"[{current_copy}/{total_copy}] Kategorie: {item['category']} | ISO: {item['filename']}", color=Colors.DARK_GRAY, level="ORDNER")

        # Bereinigung veralteter Versionen auf dem Ziel
        pat_to_use = None
        for d in distro_patterns:
            if re.search(d.get("MatchPattern", "^$"), item["filename"]):
                pat_to_use = d["MatchPattern"]
                break
        if not pat_to_use:
            pat_to_use = re.sub(r"[-_\d\.]+\.iso$", "", item["filename"])

        if dst_cat_dir.exists() and pat_to_use:
            for old_target in dst_cat_dir.glob("*.iso"):
                if old_target.name != item["filename"] and re.search(pat_to_use, old_target.name):
                    old_mb = old_target.stat().st_size / (1024 * 1024)
                    logger.log(f"[CLEANUP] Veraltete ISO auf Ziel-Laufwerk ENDGÜLTIG gelöscht: {old_target.name} ({old_mb:.2f} MB)", color=Colors.YELLOW, level="CLEANUP")
                    try:
                        old_target.unlink()
                    except Exception:
                        pass

        # Kopieren wenn nicht identisch
        need_copy = True
        if dst_iso.exists() and dst_iso.stat().st_size == item["size_bytes"]:
            logger.log(f"[BEREITS VORHANDEN] {item['filename']} ({item['size_mb']:.2f} MB) ist aktuell auf Ziel-Laufwerk.", color=Colors.GREEN, level="OK")
            need_copy = False

        if need_copy:
            logger.log(f"[KOPIERE ISO] {item['filename']} ({item['size_mb']:.2f} MB)", color=Colors.CYAN, level="LADEN")
            copy_file_with_progress(item["source"], dst_iso)
            logger.log(f"[KOPIEREN ABGESCHLOSSEN] {item['filename']}", color=Colors.GREEN, level="ERFOLG")

    if not dry_run:
        os.system("clear")
        cols = shutil.get_terminal_size(fallback=(80, 24)).columns
        banner_len = min(90, max(40, cols - 1))
        banner_border = "=" * banner_len
        print(f"{Colors.CYAN}{banner_border}{Colors.RESET}")
        print(f"{Colors.GREEN} VENTOY-KOPIERSTATUS: Alle {total_copy} ISOs erfolgreich abgeglichen!{Colors.RESET}")
        print(f"{Colors.CYAN}{banner_border}{Colors.RESET}\n")

    # Theme & ventoy.json Konfiguration
    logger.log(f"Konfiguriere Ventoy Design & Dir-Modus (Theme + Aliases) auf {target_root}...", color=Colors.CYAN, level="VENTOY")
    ventoy_dir = target_root / "ventoy"
    ventoy_json_path = ventoy_dir / "ventoy.json"

    theme_mgr = VentoyThemeManager(logger)
    active_theme = "1"
    active_record = ventoy_dir / "theme_active.txt"
    if active_record.exists():
        try:
            active_theme = active_record.read_text(encoding="utf-8").strip() or "1"
        except Exception:
            pass

    selected_theme = theme_choice if theme_choice else active_theme
    if not dry_run:
        print("")
        print(f"{Colors.CYAN}{'=' * 60}{Colors.RESET}")
        try:
            ask_theme = input("Möchtest du das Ventoy-Theme auswählen oder ändern? (j/N): ").strip().lower()
            if ask_theme in ["j", "ja", "y", "yes"]:
                selected_theme = theme_mgr.select_theme_interactive(default_choice=active_theme)
        except (KeyboardInterrupt, EOFError):
            print("")

        theme_mgr.install_theme(ventoy_dir, theme_choice=selected_theme, force=True, dry_run=dry_run)

        # ventoy.json aufbauen
        config: Dict[str, Any] = {}
        if ventoy_json_path.exists():
            try:
                config = json.loads(ventoy_json_path.read_text(encoding="utf-8"))
            except Exception:
                config = {}

        control_settings = [
            {"VTOY_DEFAULT_MENU_MODE": "1"},
            {"VTOY_TREE_VIEW_MENU_STYLE": "1"},
            {"VTOY_FILT_DIR_LEVEL": "0"},
            {"VTOY_MAX_MENU_NUM": "12"},
        ]
        config["control"] = control_settings
        config["theme"] = {
            "file": "/ventoy/theme/theme.txt",
            "gfxmode": "1920x1080",
            "display_mode": "GUI",
        }

        menu_aliases = [
            {"image": "/01_Desktop-Linux", "alias": "Desktop Linux (Ubuntu, Mint, Fedora, Arch, Zorin...)"},
            {"image": "/02_Enterprise-Server", "alias": "Enterprise Server (RHEL, Rocky, Alma, Proxmox, TrueNAS...)"},
            {"image": "/03_Security-Pentest", "alias": "Security & Pentesting (Kali, Parrot, BlackArch...)"},
            {"image": "/04_Rescue-Systeme", "alias": "Rescue & Recovery (GParted, Rescuezilla, FygoOS...)"},
            {"image": "/05_BSD-Unix", "alias": "BSD & Unix (FreeBSD, OpenBSD, NetBSD, DragonFly...)"},
        ]
        for iso_item in iso_files_to_copy:
            vtoy_path = "/" + str(iso_item["rel_path"]).replace("\\", "/")
            pretty = get_pretty_iso_name(iso_item["filename"])
            menu_aliases.append({"image": vtoy_path, "alias": pretty})

        config["menu_alias"] = menu_aliases

        try:
            ventoy_json_path.parent.mkdir(parents=True, exist_ok=True)
            ventoy_json_path.write_text(json.dumps(config, indent=4, ensure_ascii=False), encoding="utf-8")
            logger.log("Ventoy Theme & Menu-Aliases erfolgreich angewendet!", color=Colors.GREEN, level="ERFOLG")
        except Exception as e:
            logger.log(f"Fehler beim Schreiben von ventoy.json: {e}", color=Colors.RED, level="FEHLER")


# ==============================================================================
# HAUPTPROGRAMM (MAIN)
# ==============================================================================
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Linux ISO Auto-Updater & Ventoy Sync Tool (Linux Edition)",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument("--dry-run", action="store_true", help="Simulationsmodus: Keine Dateien herunterladen oder ändern.")
    parser.add_argument("--skip-download", action="store_true", help="Download-Schritt überspringen.")
    parser.add_argument("--skip-ventoy", action="store_true", help="Ventoy-Kopiervorgang überspringen.")
    parser.add_argument("--select", "--select-distros", dest="select_distros", action="store_true", help="Interaktive Distributionsauswahl aufrufen.")
    parser.add_argument("--install-ventoy", action="store_true", help="Ventoy CLI Installation/Update auf USB-Stick ausführen.")
    parser.add_argument("--change-theme", action="store_true", help="Ventoy-Theme interaktiv oder via --theme ändern.")
    parser.add_argument("--theme", type=str, help="Name oder Nummer des Ventoy-Themes (1-6 oder Name).")
    parser.add_argument("--target", type=str, help="Zielpfad oder Mountpoint für Ventoy.")
    parser.add_argument("--target-directory", type=str, help="Lokales ISO-Speicherverzeichnis (Standard: Skriptverzeichnis).")
    parser.add_argument("--log-file", type=str, default=DEFAULT_LOG_FILE, help="Name oder Pfad der Logdatei.")

    args = parser.parse_args()

    # Mehrfachstartschutz via flock
    lock = SingleInstanceLock()
    if not lock.acquire():
        print(f"\n{Colors.YELLOW}[WARNUNG] Das ISO-Update-Skript läuft bereits in einer anderen Instanz!{Colors.RESET}")
        print(f"{Colors.YELLOW}Mehrfachstart wurde verhindert.{Colors.RESET}\n")
        sys.exit(0)

    try:
        script_dir = Path(__file__).resolve().parent
        iso_dir = Path(args.target_directory).resolve() if args.target_directory else script_dir
        log_file = iso_dir / args.log_file
        archive_dir = iso_dir / "Archiv"

        logger = Logger(log_file)
        dm = DownloadManager(logger)
        chk = ChecksumVerifier(dm, logger)
        scraper_engine = DistroScraperEngine(dm)
        drive_mgr = VentoyLinuxDriveManager(logger)
        theme_mgr = VentoyThemeManager(logger)

        # SCHRITT 0: VENTOY CLI-INSTALLATION
        if args.install_ventoy:
            drive_mgr.install_ventoy_cli(tools_dir=iso_dir / "tools" / "ventoy", target_device=args.target, dry_run=args.dry_run)
            if args.skip_download and args.skip_ventoy:
                logger.log("Ventoy-Installation abgeschlossen.", color=Colors.GREEN, level="ENDE")
                return

            if not args.skip_download:
                try:
                    cont = input("\nMöchtest du nun mit dem ISO-Download / Abgleich fortfahren? (J/n): ").strip().lower()
                    if cont in ["n", "no", "nein"]:
                        if not args.skip_ventoy:
                            cp = input("Möchtest du vorhandene ISOs auf den Ventoy-Stick kopieren? (J/n): ").strip().lower()
                            if cp not in ["n", "no", "nein"]:
                                t_mount = args.target or drive_mgr.select_target_mount_interactive(total_gb_needed=10.0)
                                if t_mount:
                                    with open(iso_dir / "distros.json", "r", encoding="utf-8-sig") as f:
                                        pats = json.load(f)
                                    run_ventoy_sync(t_mount, iso_dir, pats, args.theme, args.dry_run, logger)
                        logger.log("Vorgang beendet.", color=Colors.GREEN, level="ENDE")
                        return
                except (KeyboardInterrupt, EOFError):
                    print("")
                    return

        # SCHRITT 0.5: STANDALONE THEME ÄNDERN
        if args.change_theme or (args.theme and args.skip_download):
            target_mount = args.target or drive_mgr.select_target_mount_interactive(total_gb_needed=0.1)
            if not target_mount:
                logger.log("Kein Ziel-Laufwerk gewählt. Abbruch.", color=Colors.RED, level="FEHLER")
                return

            ventoy_dir = Path(target_mount) / "ventoy"
            active_t = "1"
            if (ventoy_dir / "theme_active.txt").exists():
                try:
                    active_t = (ventoy_dir / "theme_active.txt").read_text(encoding="utf-8").strip()
                except Exception:
                    pass

            chosen_t = args.theme if args.theme else theme_mgr.select_theme_interactive(default_choice=active_t)
            theme_mgr.install_theme(ventoy_dir, theme_choice=chosen_t, force=True, dry_run=args.dry_run)

            # ventoy.json theme Eintrag aktualisieren
            v_json = ventoy_dir / "ventoy.json"
            cfg = {}
            if v_json.exists():
                try:
                    cfg = json.loads(v_json.read_text(encoding="utf-8"))
                except Exception:
                    cfg = {}
            cfg["theme"] = {
                "file": "/ventoy/theme/theme.txt",
                "gfxmode": "1920x1080",
                "display_mode": "GUI",
            }
            if not args.dry_run:
                try:
                    v_json.write_text(json.dumps(cfg, indent=4, ensure_ascii=False), encoding="utf-8")
                except Exception:
                    pass
            logger.log(f"Ventoy-Theme erfolgreich konfiguriert auf {target_mount}!", color=Colors.GREEN, level="ERFOLG")
            return

        # SCHRITT 1: ISO-UPDATE & DOWNLOAD
        distros_json_file = iso_dir / "distros.json"
        distros: List[Dict[str, Any]] = []

        if distros_json_file.exists():
            try:
                with open(distros_json_file, "r", encoding="utf-8-sig") as f:
                    distros = json.load(f)
            except Exception as e:
                logger.log(f"Fehler beim Lesen von distros.json: {e}", color=Colors.RED, level="FEHLER")

        if not distros:
            logger.log("Keine Distributionen in distros.json gefunden! Abbruch.", color=Colors.RED, level="FEHLER")
            return

        # Sicherstellen, dass Distributionen nach Gruppen und innerhalb alphabetisch sortiert sind
        distros = sorted(
            distros,
            key=lambda d: (
                CATEGORY_ORDER.index(d.get("Category", "")) if d.get("Category", "") in CATEGORY_ORDER else 999,
                d.get("Name", "").lower(),
            ),
        )

        # Interaktive Auswahl (immer zu Beginn oder bei --select)
        if not args.skip_download:
            original_json_str = json.dumps(distros, sort_keys=True)
            select_distros_interactive(distros, iso_dir, logger)
            new_json_str = json.dumps(distros, sort_keys=True)
            if original_json_str != new_json_str and not args.dry_run:
                try:
                    formatted = json.dumps(distros, indent=2, ensure_ascii=False)
                    formatted_crlf = "\r\n".join(formatted.splitlines()) + "\r\n"
                    with open(distros_json_file, "wb") as f:
                        f.write(formatted_crlf.encode("utf-8-sig"))
                except Exception:
                    pass

        # Speicherplatzprüfung
        usage = shutil.disk_usage(iso_dir)
        free_bytes = usage.free
        free_gb = free_bytes / (1024**3)

        total_bytes_needed = sum(d.get("SizeBytes", 3500 * 1024 * 1024) for d in distros if d.get("Enabled", True))
        total_gb_needed = total_bytes_needed / (1024**3)

        logger.log("=" * 60, color=Colors.CYAN, level="START")
        mode_str = "[DRY-RUN MODUS] " if args.dry_run else ""
        logger.log(f"{mode_str}Starte Linux ISO Auto-Update v{SCRIPT_VERSION} in: {iso_dir}", color=Colors.CYAN, level="INFO")
        logger.log(f"Log-Datei: {log_file}", color=Colors.DARK_GRAY, level="INFO")
        logger.log(f"[SPEICHERPLATZ] Freier Speicherplatz in {iso_dir}: {free_gb:.2f} GB | Benötigt ca.: {total_gb_needed:.2f} GB", color=Colors.DARK_GRAY, level="INFO")
        logger.log("=" * 60 + "\n", color=Colors.CYAN, level="START")

        active_distros = [d for d in distros if d.get("Enabled", True)]
        total_distros = len(active_distros)
        summary_items = []
        total_downloaded_bytes = 0

        if not args.skip_download:
            for current_idx, d in enumerate(active_distros, 1):
                name = d.get("Name", "Unbekannt")
                logger.clear_screen_distro(current_idx, total_distros, name)

                latest_info = scraper_engine.get_latest(d)
                if not latest_info:
                    logger.log(f"Konnte keine aktuelle Online-Version für {name} ermitteln.", color=Colors.RED, level="FEHLER")
                    continue

                fn = latest_info.get("Filename", "")
                if not fn.endswith(".iso") and not fn.endswith(".iso.bz2"):
                    logger.log(f"[ÜBERSPRUNGEN] Format ist kein ISO ({fn}) für {name}", color=Colors.YELLOW, level="WARNUNG")
                    continue

                logger.detail(f"Neueste Version online: {latest_info.get('Version')}")
                logger.detail(f"Gesuchte Datei:         {fn}")
                logger.detail(f"Download-URL:           {latest_info.get('Url')}")

                category = d.get("Category", "01_Desktop-Linux")
                cat_dir = iso_dir / category
                effective_fn = latest_info.get("ExtractTo", fn)
                target_path = cat_dir / effective_fn

                # Hauptverzeichnis aufräumen falls Datei dort liegt
                root_file = iso_dir / fn
                if root_file.exists() and target_path != root_file and not args.dry_run:
                    cat_dir.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(root_file), str(target_path))
                    logger.detail(f"Datei aus Hauptverzeichnis nach {category}/ einsortiert.", color=Colors.YELLOW)

                # Archiv-Routine für veraltete ISOs
                match_pat = d.get("MatchPattern")
                old_version_str = None
                if match_pat:
                    for search_folder in [iso_dir, cat_dir]:
                        if not search_folder.exists():
                            continue
                        for old_file in search_folder.glob("*.iso"):
                            if "Archiv" in str(old_file):
                                continue
                            if re.search(match_pat, old_file.name) and old_file.name != effective_fn:
                                old_mb = old_file.stat().st_size / (1024 * 1024)
                                vm = re.search(match_pat, old_file.name)
                                ver_det = vm.group(1) if vm and vm.groups() else old_file.stem
                                old_version_str = ver_det

                                if args.dry_run:
                                    logger.log(f"[ARCHIV DRY-RUN] Veraltete Datei: {old_file.name} ({old_mb:.2f} MB) -> würde nach Archiv/ verschoben", color=Colors.YELLOW, level="ARCHIV")
                                else:
                                    archive_dir.mkdir(parents=True, exist_ok=True)
                                    dest_arch = archive_dir / old_file.name
                                    shutil.move(str(old_file), str(dest_arch))
                                    logger.log(f"[ARCHIV] Veraltete Datei ins Archiv verschoben: {old_file.name} ({old_mb:.2f} MB) -> Archiv/", color=Colors.YELLOW, level="ARCHIV")

                # Prüfen ob aktuelle ISO bereits lokal vorliegt
                is_already_present = False
                if target_path.exists():
                    local_size = target_path.stat().st_size
                    online_size = dm.get_online_file_size(latest_info["Url"])
                    if online_size >= 1024 * 1024:
                        if abs(local_size - online_size) < 1024 * 1024:
                            is_already_present = True
                        else:
                            logger.log(f"[UNVOLLSTÄNDIG] Lokale Datei {effective_fn} fehlerhaft. Datei wird gelöscht und neu geladen.", color=Colors.YELLOW, level="WARNUNG")
                            target_path.unlink(missing_ok=True)
                    else:
                        if local_size > 1024 * 1024:
                            is_already_present = True
                        else:
                            target_path.unlink(missing_ok=True)

                if is_already_present:
                    file_mb = target_path.stat().st_size / (1024 * 1024)
                    logger.log("[AKTUELLES ISO]", color=Colors.GREEN, level="OK")
                    logger.detail(f"Dateiname: {effective_fn}", color=Colors.GREEN)
                    logger.detail(f"Version:   {latest_info.get('Version')}", color=Colors.GREEN)
                    logger.detail(f"Größe:     {file_mb:.2f} MB", color=Colors.GREEN)
                    logger.detail("Status:    Vorhanden (Hash-Prüfung übersprungen)", color=Colors.GREEN)
                else:
                    if args.dry_run:
                        logger.log(f"[DRY-RUN NEUE VERSION] {effective_fn} | Version: {latest_info.get('Version')}", color=Colors.GREEN, level="DRY-RUN")
                        summary_items.append(
                            {
                                "Distribution": name,
                                "Aktion": "Update (Dry-Run)" if old_version_str else "Neu (Dry-Run)",
                                "Version": f"{old_version_str} -> {latest_info.get('Version')}" if old_version_str else str(latest_info.get("Version")),
                                "Groesse": "Dry-Run",
                                "Dauer": "-",
                                "Speed": "-",
                            }
                        )
                    else:
                        logger.log(f"[UPDATE GESTARTET] Lade neue Version: {fn} | Version: {latest_info.get('Version')}", color=Colors.GREEN, level="DOWNLOAD")
                        download_dest = cat_dir / fn
                        try:
                            dl_result = dm.download_file(latest_info["Url"], download_dest, fn)
                            downloaded_bytes = dl_result.bytes
                            dl_mb = dl_result.size_mb
                            dur_str = dl_result.duration_str
                            speed_mbs = dl_result.speed_mbs
                            speed_mbits = dl_result.speed_mbits

                            logger.log(
                                f"[DOWNLOAD ERFOLGREICH] {fn} | {dl_mb:.2f} MB in {dur_str} (Ø {speed_mbs:.2f} MB/s | {speed_mbits:.1f} Mbit/s)",
                                color=Colors.GREEN,
                                level="ERFOLG",
                            )

                            # Warnung bei auffällig langsamen Mirrors (Dateien > 50 MB mit unter 4.0 MB/s bzw. 32 Mbit/s)
                            if speed_mbs < 4.0 and dl_mb > 50.0:
                                logger.log(
                                    f"[MIRROR HINWEIS] Die Download-Geschwindigkeit von {speed_mbs:.2f} MB/s ({speed_mbits:.1f} Mbit/s) für '{name}' war auffallend niedrig.",
                                    color=Colors.YELLOW,
                                    level="WARNUNG",
                                )
                                logger.detail(f"Aktuelle Quelle: {latest_info['Url']}")
                                logger.detail(f"Empfehlung: Schnelleren alternativen Mirror für '{name}' in distros.json hinterlegen.")

                            # BZ2 Dekomprimierung falls nötig
                            if latest_info.get("ExtractTo"):
                                extracted_iso = cat_dir / latest_info["ExtractTo"]
                                logger.log(f"[ENTPACKEN] Dekomprimiere {fn} nach {latest_info['ExtractTo']}...", color=Colors.CYAN, level="INFO")
                                if decompress_bz2(download_dest, extracted_iso):
                                    download_dest.unlink(missing_ok=True)
                                    target_path = extracted_iso
                                    logger.log(f"[ENTPACKT] {latest_info['ExtractTo']} erfolgreich entpackt!", color=Colors.GREEN, level="ERFOLG")
                                else:
                                    logger.log(f"[WARNUNG] Entpacken von {fn} fehlgeschlagen.", color=Colors.YELLOW, level="WARNUNG")

                            # Prüfsummenvalidierung
                            valid = chk.verify_iso_checksum(
                                target_path,
                                latest_info["Url"],
                                latest_info.get("ExtractTo", fn),
                                latest_info.get("ChecksumUrl"),
                            )
                            if not valid:
                                logger.log(f"[FEHLER] Prüfsumme von {target_path.name} IST UNGÜLTIG! Datei wird gelöscht.", color=Colors.RED, level="FEHLER")
                                target_path.unlink(missing_ok=True)
                            else:
                                total_downloaded_bytes += downloaded_bytes
                                summary_items.append(
                                    {
                                        "Distribution": name,
                                        "Aktion": "Update" if old_version_str else "Neu geladen",
                                        "Version": f"{old_version_str} -> {latest_info.get('Version')}" if old_version_str else str(latest_info.get("Version")),
                                        "Groesse": f"{dl_mb:.2f} MB",
                                        "Dauer": dur_str,
                                        "Speed": f"Ø {speed_mbs:.2f} MB/s",
                                    }
                                )
                        except Exception as e:
                            logger.log(f"[DOWNLOAD FEHLER] {e}", color=Colors.RED, level="FEHLER")
                            download_dest.unlink(missing_ok=True)
                            target_path.unlink(missing_ok=True)
                            logger.log(f"[CLEANUP] Unvollständige Datei {fn} wurde gelöscht.", color=Colors.YELLOW, level="CLEANUP")

                print("")

        logger.log("=" * 60, color=Colors.CYAN, level="ENDE")
        logger.log("ISO Auto-Update-Vorgang abgeschlossen.", color=Colors.CYAN, level="ENDE")

        # Übersichtstabelle
        if summary_items:
            print("")
            cols = shutil.get_terminal_size(fallback=(80, 24)).columns
            title = "ÜBERSICHT: VERFÜGBARE UPDATES / NEUE ISOS (DRY-RUN)" if args.dry_run else "ÜBERSICHT: HERUNTERGELADENE & AKTUALISIERTE ISOS"
            logger.log(title, color=Colors.CYAN, level="INFO")

            if not args.dry_run and cols >= 110:
                header = f"   {'Distribution':<24} | {'Status':<14} | {'Version':<20} | {'Größe':>10} | {'Dauer':>9} | {'Ø-Speed':>14}"
                tbl_border = "-" * min(len(header), max(40, cols - 1))
                print(f"{Colors.DARK_GRAY}{tbl_border}{Colors.RESET}")
                print(f"{Colors.YELLOW}{header}{Colors.RESET}")
                print(f"{Colors.DARK_GRAY}{tbl_border}{Colors.RESET}")
                logger._write_file(header)
                for s in summary_items:
                    row = f"   {s['Distribution']:<24} | {s['Aktion']:<14} | {s['Version']:<20} | {s['Groesse']:>10} | {s.get('Dauer', '-'):>9} | {s.get('Speed', '-'):>14}"
                    color = Colors.CYAN if "Update" in s["Aktion"] else Colors.GREEN
                    print(f"{color}{row}{Colors.RESET}")
                    logger._write_file(row)
            elif cols < 85:
                header = f"   {'Distribution':<22} | {'Status':<13} | {'Version':<18} | {'Größe':>10}"
                tbl_border = "-" * min(len(header), max(40, cols - 1))
                print(f"{Colors.DARK_GRAY}{tbl_border}{Colors.RESET}")
                print(f"{Colors.YELLOW}{header}{Colors.RESET}")
                print(f"{Colors.DARK_GRAY}{tbl_border}{Colors.RESET}")
                logger._write_file(header)
                for s in summary_items:
                    row = f"   {s['Distribution']:<22} | {s['Aktion']:<13} | {s['Version']:<18} | {s['Groesse']:>10}"
                    color = Colors.CYAN if "Update" in s["Aktion"] else Colors.GREEN
                    print(f"{color}{row}{Colors.RESET}")
                    logger._write_file(row)
            else:
                header = f"   {'Distribution':<26} | {'Status':<16} | {'Version':<24} | {'Größe':>12}"
                tbl_border = "-" * min(len(header), max(40, cols - 1))
                print(f"{Colors.DARK_GRAY}{tbl_border}{Colors.RESET}")
                print(f"{Colors.YELLOW}{header}{Colors.RESET}")
                print(f"{Colors.DARK_GRAY}{tbl_border}{Colors.RESET}")
                logger._write_file(header)
                for s in summary_items:
                    row = f"   {s['Distribution']:<26} | {s['Aktion']:<16} | {s['Version']:<24} | {s['Groesse']:>12}"
                    color = Colors.CYAN if "Update" in s["Aktion"] else Colors.GREEN
                    print(f"{color}{row}{Colors.RESET}")
                    logger._write_file(row)

            print(f"{Colors.DARK_GRAY}{tbl_border}{Colors.RESET}\n")

        # SCHRITT 2: VENTOY SYNCHRONISIERUNG
        if not args.skip_ventoy:
            target_mount = args.target
            if not target_mount:
                try:
                    ask_ventoy = input("\nMöchtest du die ISO-Ordnerstruktur jetzt auf einen Ventoy-Stick synchronisieren? (J/n): ").strip().lower()
                    if ask_ventoy in ["n", "no", "nein"]:
                        logger.log("Ventoy-Synchronisierung übersprungen.", color=Colors.GREEN, level="ENDE")
                        return
                except (KeyboardInterrupt, EOFError):
                    print("")
                    return

                target_mount = drive_mgr.select_target_mount_interactive(total_gb_needed=total_gb_needed)

            if target_mount:
                run_ventoy_sync(
                    target_drive=target_mount,
                    source_dir=iso_dir,
                    distro_patterns=distros,
                    theme_choice=args.theme,
                    dry_run=args.dry_run,
                    logger=logger,
                )

    finally:
        lock.release()


if __name__ == "__main__":
    main()
