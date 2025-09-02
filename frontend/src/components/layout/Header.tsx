import React from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Navbar, Nav, Container } from 'react-bootstrap';

function Header() {
  return (
    <Navbar bg="success" variant="dark" expand="lg" sticky="top">
      <Container>
        <Navbar.Brand href="#home">Compound Assistant</Navbar.Brand>
        <Navbar.Toggle aria-controls="basic-navbar-nav" />
        <Navbar.Collapse id="basic-navbar-nav" className="justify-content-between">
          <Nav className="me-auto">
            {/* <Nav.Link href="#home">Home</Nav.Link>
            <Nav.Link href="#docs">Documentation</Nav.Link>
            <Nav.Link href="#about">About</Nav.Link> */}
          </Nav>
          <div className="wallet-connect-container">
            <ConnectButton />
          </div>
        </Navbar.Collapse>
      </Container>
    </Navbar>
  );
}

export default Header; 