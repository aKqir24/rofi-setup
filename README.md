# rofi-setup

The scripts I use in almost everything I want to access in the a my desktop. Disclaimer, some of the scripts are not entirely mine, namely the `bluetooth`, `wifi`, and `powermenu`.

<video controls width="600">
  <source src="preview.mp4" type="video/mp4">
  Your browser does not support the video tag.
</video>


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
```bash
    bash show.sh \
        [ launcher, emoji, bluetooth, powermenu, wifi ]
```
