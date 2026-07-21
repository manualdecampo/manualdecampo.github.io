# Daniel Escobar Rodríguez — @manualdecampo

Sitio personal estático para GitHub Pages.

- Perfil canónico: `Daniel Escobar Rodríguez`
- Usuario público: `@manualdecampo`
- Publicación objetivo: `https://manualdecampo.github.io/`
- Sin frameworks, analítica ni dependencias externas

## Archivo editorial

El sitio conserva copias estáticas, legibles e indexables de:

- 2 columnas publicadas en Portal Socialista
- 12 stories publicadas en Medium
- el perfil futbolístico de Daniel Escobar Rodríguez en En El Camarín

Cada texto tiene una URL propia, enlace canónico local, datos estructurados de
artículo y un vínculo visible hacia la publicación original. El índice completo
también se distribuye mediante `sitemap.xml`, `feed.xml`, `articles.json` y
`llms.txt`.

Para reconstruir el archivo desde sus fuentes públicas:

```sh
ruby scripts/import_publications.rb
```
