import xmltree, htmlparser

let x = parseHtml readFile "./play.html"
echo x
echo x.len