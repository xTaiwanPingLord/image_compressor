import os
import re
import traceback
from PIL import Image

INPUT_FOLDER = "input_long"
INPUT_FOLDER2 = "input_square"
OUTPUT_FOLDER = "output"
MAX_WIDTH = 1000
MAX_HEIGHT = 1500
MAX_IMAGES = 18
MAX_FILESIZE = 495 * 1024  # 495 KB

# For second input folder
COMP_MAX_SIZE = 1000  # 1000x1000 px
COMP_MAX_FILESIZE = 990 * 1024  # 990 KB

OUTPUT_FILE_PREFIX = "223_ssd"


def natural_sort_key(s):
    matches = re.findall(r"_(\d+)", s)
    return int(matches[-1]) if matches else 0


def resize_image(img):
    """Resize image if width > MAX_WIDTH while keeping aspect ratio."""
    if img.width > MAX_WIDTH:
        ratio = MAX_WIDTH / img.width
        new_size = (MAX_WIDTH, int(img.height * ratio))
        return img.resize(new_size, Image.LANCZOS)
    return img


def concat_images_vertically(images):
    """Concatenate list of images vertically."""
    widths = [img.width for img in images]
    heights = [img.height for img in images]

    total_height = sum(heights)
    max_width = max(widths)

    new_img = Image.new("RGB", (max_width, total_height), (255, 255, 255))

    y_offset = 0
    for img in images:
        new_img.paste(img, (0, y_offset))
        y_offset += img.height

    return new_img


def split_image(img):
    """Split image into chunks that meet MAX_HEIGHT."""
    parts = []
    y = 0
    while y < img.height:
        part = img.crop((0, y, img.width, min(y + MAX_HEIGHT, img.height)))
        parts.append(part)
        y += MAX_HEIGHT
    return parts


def save_with_compression(img, path, max_filesize):
    """Save image ensuring it's under max_filesize."""
    quality = 100
    while quality >= 10:
        img.save(path, format="JPEG", quality=quality, optimize=True)
        filesize = os.path.getsize(path)
        print(f"  Trying quality {quality}: {filesize / 1024:.1f} KB")
        if filesize <= max_filesize:
            print(f"  ✓ Success at quality {quality}")
            break
        quality -= 5
    else:
        print(f"  ⚠ Warning: Could not compress below {max_filesize / 1024:.1f} KB even at quality 10")


def process_first_folder():
    try:
        # Collect images, sort by name according to number after last underscore, for example: starriver_4b_1.jpg, starriver_4b_2.jpg, ...
        files = [f for f in os.listdir(INPUT_FOLDER) if f.lower().endswith((".jpg", ".jpeg", ".png"))]
        files.sort(key=natural_sort_key)
        print(f"Found {len(files)} images in {INPUT_FOLDER}")

        images = [resize_image(Image.open(os.path.join(INPUT_FOLDER, f)).convert("RGB")) for f in files]

        # Concatenate all
        combined = concat_images_vertically(images)

        # Split
        parts = split_image(combined)

        # Ensure max images constraint
        if len(parts) > MAX_IMAGES:
            print(f"Warning: More than {MAX_IMAGES} parts generated, truncating.")
            parts = parts[:MAX_IMAGES]

        # Save
        for i, part in enumerate(parts):
            out_path = os.path.join(OUTPUT_FOLDER, f"{OUTPUT_FILE_PREFIX}_{i+1}.jpg")
            save_with_compression(part, out_path, MAX_FILESIZE)
            print(f"Saved {out_path}")
    except Exception as e:
        print(f"Error processing first folder: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()


def process_second_folder():
    try:
        files = [f for f in os.listdir(INPUT_FOLDER2) if f.lower().endswith((".jpg", ".jpeg", ".png"))]
        print(f"Found {len(files)} images in {INPUT_FOLDER2}")

        for f in files:
            print(f"Processing {f}...")
            img = Image.open(os.path.join(INPUT_FOLDER2, f)).convert("RGB")

            # Resize keeping aspect ratio within COMP_MAX_SIZE
            ratio = min(COMP_MAX_SIZE / img.width, COMP_MAX_SIZE / img.height, 1)
            new_size = (int(img.width * ratio), int(img.height * ratio))
            img = img.resize(new_size, Image.LANCZOS)

            # Save with compression
            filename, _ = os.path.splitext(f)
            out_path = os.path.join(OUTPUT_FOLDER, f"_comp_{filename}.jpg")
            save_with_compression(img, out_path, COMP_MAX_FILESIZE)
            print(f"Saved {out_path}")
    except Exception as e:
        print(f"Error processing second folder: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()


def main():
    if not os.path.exists(OUTPUT_FOLDER):
        os.makedirs(OUTPUT_FOLDER)

    process_first_folder()
    process_second_folder()


if __name__ == "__main__":
    main()
