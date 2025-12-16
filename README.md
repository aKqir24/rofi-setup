# rofi-setup

The scripts I use in almost everything I want to access in the a my desktop. Disclaimer, some of the scripts are not entirely mine, namely the `bluetooth`, `wifi`, and `powermenu`.

https://github.com/user-attachments/assets/ab7b87f9-fe97-48f2-b575-f2621c11c761


# Setup
- __DEPENDENCIES__
    - rofi >= 1.7.5
    - rofi-emoji _(optional)_
    - iwd _(for wifi)_

- __INSTALLATION__

    ```bash
    sudo apt install rofi iwd

    # Please setup pacstall to use this
    sudo pacstall -I rofi-emoji-git
    ```

# Usage

- With my dotfiles
```bash
    bash show.sh \
        [ launcher, emoji, bluetooth, powermenu, wifi ]
```

- Manually
```bash 
    # You might need to configure the theme
    sh [wifi.sh, bluetooth.sh]
