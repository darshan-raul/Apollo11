import Link from 'next/link'
import fetch from 'isomorphic-unfetch'


export default function Crypto({cryptos}) {
  return (
    <>
      <h1>Cryptos </h1>
      
      <ul>
        {cryptos.map((crypto) => (
            <li>{crypto.name}</li>
        ))}
      </ul>
      
      <h2>
        <Link href="/">
          <a>Back to home</a>
        </Link>
      </h2>


    </>
  )
}

export const getStaticProps=async() => {

    const res = await fetch ('http://localhost:8000')
    const cryptos = await res.json();
    return {
        props: {
            cryptos
        }
    }

}
