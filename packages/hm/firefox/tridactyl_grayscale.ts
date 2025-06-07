// Needs to be manually registered using:

// 
// autocmd TriStart .* js -s -r ./grayscale.js
// autocmd DocStart .* js -s -r ./grayscale.js
// 
// Or for specific site using
// 
// autocmd TriStart (www\.)?youtube.com js -s -r ./grayscale.js
// autocmd DocStart (www\.)?youtube.com js -s -r ./grayscale.js


async function main() {
  while (true) {
    window.document.documentElement.style.filter = "grayscale(90%)"
    await new Promise(r => setTimeout(r, 1000 * 1800)) // set again after 30m
  }
}

main()

