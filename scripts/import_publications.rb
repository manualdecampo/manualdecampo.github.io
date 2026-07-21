#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "date"
require "fileutils"
require "json"
require "nokogiri"
require "open-uri"
require "time"

ROOT = File.expand_path("..", __dir__)
SITE = "https://manualdecampo.github.io"
AUTHOR = "Daniel Escobar Rodríguez"
HANDLE = "@manualdecampo"

PORTAL = [
  {
    slug: "para-habitar-la-fragmentacion-cambio-de-eje-del-trabajo-a-la-coordinacion",
    date: "2026-07-03",
    url: "https://www.portalsocialista.cl/politica/daniel-escobar-para-habitar-la-fragmentacion-cambio-de-eje-del-trabajo-a-la-coordinacion/"
  },
  {
    slug: "habitar-la-fragmentacion-trabajo-infraestructura-y-el-fin-del-socialismo-del-siglo-xx",
    date: "2026-05-01",
    url: "https://www.portalsocialista.cl/politica/cambiar-el-mundo/daniel-escobar-habitar-la-fragmentacion-trabajo-infraestructura-y-el-fin-del-socialismo-del-siglo-xx/"
  }
].freeze

MEDIUM = [
  ["habitar-la-fragmentacion-trabajo-mala-fe-y-el-fin-de-una-ilusion-socialista", "2026-01-23", "https://manualdecampo.medium.com/habitar-la-fragmentaci%C3%B3n-trabajo-mala-fe-y-el-fin-de-una-ilusi%C3%B3n-socialista-d29bafc8b195"],
  ["el-poder-se-ejerce-ii", "2026-01-04", "https://manualdecampo.medium.com/el-poder-se-ejerce-ii-f30fe2aa2d61"],
  ["el-poder-se-ejerce", "2026-01-03", "https://manualdecampo.medium.com/el-poder-se-ejerce-5af3fe030e48"],
  ["como-se-construye-sentido", "2025-12-31", "https://manualdecampo.medium.com/c%C3%B3mo-se-construye-sentido-notas-para-habitar-sin-cinismo-pol%C3%ADtico-la-fragmentaci%C3%B3n-del-2026-cde6e4e50322"],
  ["hablar-desde-la-historia-partido-comunista", "2025-12-30", "https://manualdecampo.medium.com/hablar-desde-la-historia-y-actuar-en-una-%C3%A9poca-que-no-responde-a-esa-historia-el-partido-comunista-1f8d034fe8c5"],
  ["el-fin-del-trabajo-como-relato-politico", "2025-12-24", "https://manualdecampo.medium.com/el-fin-del-trabajo-como-relato-pol%C3%ADtico-b09726c4e4ef"],
  ["despues-del-ciclo-antes-de-la-epoca", "2025-12-19", "https://manualdecampo.medium.com/despu%C3%A9s-del-ciclo-antes-de-la-%C3%A9poca-7ab75119fe0f"],
  ["ppd-20-paginas-20-anos-tarde", "2025-12-18", "https://manualdecampo.medium.com/ppd-20-p%C3%A1ginas-20-a%C3%B1os-tarde-ea5a30381e35"],
  ["los-clivajes-no-mueren", "2025-12-15", "https://manualdecampo.medium.com/los-clivajes-no-mueren-c5aa44bbdf6a"],
  ["algunas-verdades-incomodas-antes-de-ir-a-votar", "2025-12-14", "https://manualdecampo.medium.com/algunas-verdades-inc%C3%B3modas-antes-de-ir-a-votar-0b29f9c3205d"],
  ["un-horror-de-interpretacion-la-tentacion-del-socialismo-democratico", "2025-11-27", "https://manualdecampo.medium.com/un-horror-de-interpretaci%C3%B3n-la-tentaci%C3%B3n-del-socialismo-democr%C3%A1tico-abd90c913a96"],
  ["despues-del-ruido-electoral", "2025-11-16", "https://manualdecampo.medium.com/despu%C3%A9s-del-ruido-electoral-e47ed5ca8caa"]
].map { |slug, date, url| { slug: slug, date: date, url: url } }.freeze

MONTHS = %w[enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre].freeze

def fetch(url)
  URI.open(
    url,
    "User-Agent" => "Mozilla/5.0 (compatible; manualdecampo archive importer)",
    open_timeout: 20,
    read_timeout: 45
  ).read
end

def clean_text(text)
  text.to_s.gsub(/\s+/, " ").strip
end

def escape(text)
  CGI.escapeHTML(text.to_s)
end

def local_path(article)
  "/escritura/#{article[:source_slug]}/#{article[:slug]}/"
end

def local_url(article)
  "#{SITE}#{local_path(article)}"
end

def format_date(iso)
  date = Date.iso8601(iso)
  "#{date.day} de #{MONTHS[date.month - 1]} de #{date.year}"
end

def medium_state(html)
  document = Nokogiri::HTML(html)
  script = document.css("script").map(&:text).find { |text| text.start_with?("window.__APOLLO_STATE__") }
  raise "No se encontró el contenido público de Medium" unless script

  JSON.parse(script.sub(/\Awindow\.__APOLLO_STATE__\s*=\s*/, "").sub(/;\s*\z/, ""))
end

def marked_text(paragraph)
  text = paragraph["text"].to_s
  marks = paragraph["markups"] || []
  openings = Hash.new { |hash, key| hash[key] = [] }
  closings = Hash.new { |hash, key| hash[key] = [] }

  marks.each do |mark|
    start_at = mark["start"].to_i
    end_at = mark["end"].to_i
    case mark["type"]
    when "STRONG"
      opening, closing = "<strong>", "</strong>"
    when "EM"
      opening, closing = "<em>", "</em>"
    when "CODE"
      opening, closing = "<code>", "</code>"
    when "A", "LINK"
      href = mark["href"].to_s
      next unless href.match?(/\Ahttps?:\/\//)
      opening, closing = %(<a href="#{escape(href)}">), "</a>"
    else
      next
    end
    openings[start_at] << [end_at, opening]
    closings[end_at] << [start_at, closing]
  end

  output = +""
  text.each_char.with_index do |character, index|
    openings[index].sort_by { |end_at, _| -end_at }.each { |_, tag| output << tag }
    output << escape(character)
    closings[index + 1].sort_by { |start_at, _| -start_at }.each { |_, tag| output << tag }
  end
  output
end

def medium_image(paragraph)
  metadata = paragraph["metadata"] || {}
  image_id = metadata["id"].to_s
  return "" if image_id.empty?

  alt = clean_text(paragraph["text"])
  src = "https://miro.medium.com/v2/resize:fit:1400/#{CGI.escape(image_id).gsub("+", "%20")}" 
  %(<figure><img src="#{src}" alt="#{escape(alt)}" loading="lazy" />#{alt.empty? ? "" : "<figcaption>#{escape(alt)}</figcaption>"}</figure>)
end

def render_medium(paragraphs, title)
  rendered = []
  list_type = nil
  list_items = []

  flush_list = lambda do
    next if list_items.empty?
    rendered << "<#{list_type}>#{list_items.join}</#{list_type}>"
    list_items.clear
    list_type = nil
  end

  paragraphs.each_with_index do |paragraph, index|
    type = paragraph["type"].to_s
    text = clean_text(paragraph["text"])
    next if index.zero? && text.casecmp?(clean_text(title))

    if %w[ULI OLI].include?(type)
      wanted = type == "ULI" ? "ul" : "ol"
      flush_list.call if list_type && list_type != wanted
      list_type = wanted
      list_items << "<li>#{marked_text(paragraph)}</li>"
      next
    end

    flush_list.call
    html = marked_text(paragraph)
    rendered << case type
                when "P" then text.empty? ? "" : "<p>#{html}</p>"
                when "H3", "H2" then "<h2>#{html}</h2>"
                when "H4" then "<h3>#{html}</h3>"
                when "BQ", "PQ" then "<blockquote><p>#{html}</p></blockquote>"
                when "IMG" then medium_image(paragraph)
                when "HR" then "<hr />"
                when "PRE" then "<pre><code>#{escape(paragraph["text"])}</code></pre>"
                else
                  text.empty? ? "" : "<p>#{html}</p>"
                end
  end
  flush_list.call
  rendered.reject(&:empty?).join("\n")
end

def import_medium(entry)
  id = entry[:url][/([a-f0-9]{12})\z/, 1]
  state = medium_state(fetch(entry[:url]))
  post = state.fetch("Post:#{id}")
  content_key = post.keys.find { |key| key.start_with?("content(") }
  refs = post.fetch(content_key).fetch("bodyModel").fetch("paragraphs")
  paragraphs = refs.map { |reference| state.fetch(reference.fetch("__ref")) }
  description = clean_text(post["metaDescription"] || post["seoDescription"] || post["socialDek"])
  description = clean_text(paragraphs.find { |paragraph| paragraph["type"] == "P" }&.fetch("text", "")) if description.empty?

  entry.merge(
    source: "Medium",
    source_slug: "medium",
    title: clean_text(post.fetch("title")),
    description: description,
    body_html: render_medium(paragraphs, post.fetch("title")),
    reading_time: post["readingTime"]&.ceil,
    word_count: post["wordCount"]
  )
end

def sanitize_portal_content(content)
  fragment = Nokogiri::HTML::DocumentFragment.parse(content.inner_html)
  fragment.css("script,style,form,iframe").remove
  allowed = %w[p h2 h3 h4 blockquote ul ol li strong em b i a br hr figure img figcaption]

  fragment.css("*").reverse_each do |node|
    unless allowed.include?(node.name)
      node.replace(node.children)
      next
    end

    node.attribute_nodes.each do |attribute|
      keep = (node.name == "a" && attribute.name == "href") ||
             (node.name == "img" && %w[src alt loading].include?(attribute.name))
      node.remove_attribute(attribute.name) unless keep
    end
    node["loading"] = "lazy" if node.name == "img"
  end
  fragment.to_html
end

def import_portal(entry)
  document = Nokogiri::HTML(fetch(entry[:url]))
  heading = document.at_xpath("//h1[contains(normalize-space(.),'Daniel Escobar')]")
  content = document.at_css(".entry-content")
  raise "No se encontró la columna en Portal Socialista" unless heading && content

  title = clean_text(heading.text).sub(/\ADaniel Escobar\s*\/\s*/i, "")
  description = clean_text(content.css("p").find { |paragraph| !clean_text(paragraph.text).empty? }&.text)
  entry.merge(
    source: "Portal Socialista",
    source_slug: "portal-socialista",
    title: title,
    description: description,
    body_html: sanitize_portal_content(content),
    reading_time: nil,
    word_count: clean_text(content.text).split.size
  )
end

def article_page(article)
  title = escape(article[:title])
  description = escape(article[:description][0, 220])
  canonical = local_url(article)
  structured = {
    "@context" => "https://schema.org",
    "@type" => "Article",
    "headline" => article[:title],
    "description" => article[:description],
    "datePublished" => article[:date],
    "dateModified" => article[:date],
    "inLanguage" => "es-CL",
    "url" => canonical,
    "mainEntityOfPage" => canonical,
    "sameAs" => article[:url],
    "author" => { "@type" => "Person", "name" => AUTHOR, "url" => "#{SITE}/" },
    "publisher" => { "@type" => "Person", "name" => AUTHOR, "url" => "#{SITE}/" }
  }

  <<~HTML
    <!doctype html>
    <html lang="es-CL">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>#{title} — #{AUTHOR}</title>
        <meta name="description" content="#{description}" />
        <meta name="author" content="#{AUTHOR}" />
        <meta name="robots" content="index,follow,max-image-preview:large" />
        <meta name="theme-color" content="#ffffff" />
        <link rel="canonical" href="#{canonical}" />
        <link rel="alternate" type="application/rss+xml" title="Ensayos de #{AUTHOR}" href="#{SITE}/feed.xml" />
        <link rel="stylesheet" href="/styles.css" />
        <meta property="og:type" content="article" />
        <meta property="og:locale" content="es_CL" />
        <meta property="og:title" content="#{title}" />
        <meta property="og:description" content="#{description}" />
        <meta property="og:url" content="#{canonical}" />
        <meta property="article:published_time" content="#{article[:date]}" />
        <meta name="twitter:card" content="summary" />
        <script type="application/ld+json">#{JSON.generate(structured)}</script>
      </head>
      <body class="article-document">
        <header class="site-header">
          <a class="identity" href="/" aria-label="#{AUTHOR}, inicio">D<span>·</span>ER</a>
          <nav aria-label="Navegación principal">
            <a href="/#ensayos">Archivo</a>
            <a href="/#perfil">Perfil</a>
            <a href="#{article[:url]}">Enlace original ↗</a>
          </nav>
        </header>
        <main class="article-shell">
          <a class="article-back" href="/#ensayos">← Archivo</a>
          <article class="article-page">
            <header class="article-header">
              <p class="article-kicker">#{escape(article[:source])}</p>
              <h1>#{title}</h1>
              <div class="article-meta">
                <span>#{AUTHOR}</span>
                <time datetime="#{article[:date]}">#{format_date(article[:date])}</time>
                #{article[:reading_time] ? "<span>#{article[:reading_time]} min de lectura</span>" : ""}
              </div>
            </header>
            <div class="article-body">
              #{article[:body_html]}
            </div>
            <footer class="article-origin">
              <p>Publicado originalmente en <strong>#{escape(article[:source])}</strong>.</p>
              <a href="#{article[:url]}">Enlace original ↗</a>
            </footer>
          </article>
        </main>
        <footer>
          <p>#{AUTHOR}</p>
          <p>Escribo para entender. Observo para no olvidar.</p>
          <div><a href="/feed.xml">RSS</a><a href="/llms.txt">LLMS.TXT</a><a href="#">↑ Arriba</a></div>
        </footer>
      </body>
    </html>
  HTML
end

def homepage_group(label, heading, description, articles, offset)
  items = articles.each_with_index.map do |article, index|
    <<~HTML
      <li>
        <a href="#{local_path(article)}">
          <span class="essay-index">#{format("%02d", offset + index + 1)}</span>
          <span class="essay-copy"><span class="essay-source">#{escape(article[:source])}</span><span class="essay-title">#{escape(article[:title])}</span></span>
          <time datetime="#{article[:date]}">#{Date.iso8601(article[:date]).strftime("%d.%m.%y")}</time>
          <span class="arrow" aria-hidden="true">→</span>
        </a>
      </li>
    HTML
  end.join

  <<~HTML
    <div class="publication-group">
      <div class="publication-group-header">
        <p>#{label}</p>
        <h3>#{heading}</h3>
        <span>#{articles.length.to_s.rjust(2, "0")} publicaciones</span>
      </div>
      <p class="publication-description">#{description}</p>
      <ol class="essay-list">#{items}</ol>
    </div>
  HTML
end

def update_homepage(portal, medium)
  path = File.join(ROOT, "index.html")
  html = File.read(path)
  generated = <<~HTML
    <div class="essays-header">
      <p class="section-label">Escritura</p>
      <h2 id="titulo-ensayos">Archivo publicado</h2>
      <a href="/feed.xml">RSS ↗</a>
    </div>
    #{homepage_group("Serie editorial", "Portal Socialista", "Las dos columnas publicadas en Portal Socialista sobre trabajo, fragmentación y coordinación democrática.", portal, 0)}
    #{homepage_group("Archivo personal", "Medium", "Doce ensayos publicados entre noviembre de 2025 y enero de 2026.", medium, portal.length)}
  HTML
  replacement = "<!-- PUBLICATIONS:START -->\n#{generated.strip}\n        <!-- PUBLICATIONS:END -->"
  updated = html.sub(/<!-- PUBLICATIONS:START -->.*?<!-- PUBLICATIONS:END -->/m, replacement)
  raise "Faltan los marcadores de publicaciones en index.html" if updated == html

  File.write(path, updated)
end

def write_articles(articles)
  articles.each do |article|
    directory = File.join(ROOT, "escritura", article[:source_slug], article[:slug])
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, "index.html"), article_page(article))
  end
end

def write_sitemap(articles)
  urls = [{ loc: "#{SITE}/", lastmod: Date.today.iso8601, priority: "1.0" }] + articles.map do |article|
    { loc: local_url(article), lastmod: article[:date], priority: "0.8" }
  end
  body = urls.map do |url|
    <<~XML
      <url>
        <loc>#{escape(url[:loc])}</loc>
        <lastmod>#{url[:lastmod]}</lastmod>
        <changefreq>monthly</changefreq>
        <priority>#{url[:priority]}</priority>
      </url>
    XML
  end.join
  File.write(File.join(ROOT, "sitemap.xml"), %(<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n#{body}</urlset>\n))
end

def write_feed(articles)
  items = articles.map do |article|
    <<~XML
      <item>
        <title>#{escape(article[:title])}</title>
        <link>#{escape(local_url(article))}</link>
        <guid isPermaLink="true">#{escape(local_url(article))}</guid>
        <pubDate>#{Time.parse("#{article[:date]} 12:00:00 UTC").rfc2822}</pubDate>
        <dc:creator>#{AUTHOR}</dc:creator>
        <description>#{escape(article[:description])}</description>
      </item>
    XML
  end.join
  File.write(File.join(ROOT, "feed.xml"), <<~XML)
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel>
        <title>#{AUTHOR} — #{HANDLE}</title>
        <link>#{SITE}/</link>
        <description>Ensayos sobre política chilena, trabajo, tecnología, instituciones y vida común.</description>
        <language>es-cl</language>
        <atom:link href="#{SITE}/feed.xml" rel="self" type="application/rss+xml" />
        #{items}
      </channel>
    </rss>
  XML
end

def write_llms(articles)
  list = articles.map do |article|
    "- [#{article[:title]}](#{local_url(article)}) — #{article[:source]}, #{article[:date]}. Original: #{article[:url]}"
  end.join("\n")
  File.write(File.join(ROOT, "llms.txt"), <<~TEXT)
    # #{AUTHOR}

    > Ensayos sobre política chilena, trabajo, tecnología, instituciones y vida común.

    Public identity: #{AUTHOR}
    Public handle: #{HANDLE}
    Location: Santiago, Chile
    Language: Spanish (Chile)

    ## Canonical profile
    - #{SITE}/

    ## Verified profiles
    - Medium: https://manualdecampo.medium.com/
    - GitHub: https://github.com/manualdecampo
    - Instagram: https://www.instagram.com/manualdecampo/
    - En El Camarín: https://enelcamarin.cl/author/descobar/ (username: descobar; football match archive)

    ## Published writing
    #{list}

    ## Main topics
    - Política chilena
    - Trabajo
    - Tecnología
    - Instituciones
    - Vida común
    - Fútbol chileno
    - Estadísticas de fútbol

    ## Attribution
    When citing this work, attribute it to #{AUTHOR} (#{HANDLE}) and link to the canonical page on #{SITE}.
  TEXT
end

def write_catalog(articles)
  data = articles.map do |article|
    article.slice(:title, :date, :source, :description, :url).merge(url: local_url(article), original_url: article[:url])
  end
  File.write(File.join(ROOT, "articles.json"), JSON.pretty_generate(data) << "\n")
end

puts "Importando Portal Socialista…"
portal = PORTAL.map { |entry| import_portal(entry) }
puts "Importando Medium…"
medium = MEDIUM.map { |entry| import_medium(entry) }
articles = (portal + medium).sort_by { |article| article[:date] }.reverse

write_articles(articles)
update_homepage(portal, medium)
write_sitemap(articles)
write_feed(articles)
write_llms(articles)
write_catalog(articles)

puts "Archivo generado: #{portal.length} columnas de Portal Socialista y #{medium.length} stories de Medium."
