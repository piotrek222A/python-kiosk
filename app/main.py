#!/usr/bin/env python3
import os
import subprocess
import tkinter as tk
from tkinter import messagebox

def logout():
    sid = os.environ.get("XDG_SESSION_ID")
    if not sid:
        messagebox.showerror(
            "Error",
            "Missing XDG_SESSION_ID. Run the application inside a graphical session (not from TTY/SSH)."
        )
        return

    try:
        subprocess.run(["loginctl", "terminate-session", sid], check=True)
    except subprocess.CalledProcessError as e:
        messagebox.showerror("Error", f"Logout failed (loginctl): {e}")

def main():
    root = tk.Tk()
    root.title("Kiosk")
    root.attributes("-fullscreen", True)
    root.configure(bg="black")

    frame = tk.Frame(root, bg="black")
    frame.pack(expand=True)

    label = tk.Label(
        frame,
        text="Hello world",
        fg="white",
        bg="black",
        font=("DejaVu Sans", 48, "bold"),
    )
    label.pack(pady=40)

    btn = tk.Button(
        frame,
        text="Logout",
        font=("DejaVu Sans", 28),
        width=12,
        height=2,
        command=logout,
    )
    btn.pack(pady=20)

    root.mainloop()

if __name__ == "__main__":
    main()